{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module GitHub
  ( latestTag,
    latestTagAfterWhere,
    latestTagWhere,
    changelog,
    changelogWhere,
    downloadText,
    downloadFirstText,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (catch, displayException)
import Control.Monad (guard, unless)
import Data.Aeson (FromJSON, eitherDecode)
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Char (isAlphaNum, isDigit, toLower)
import Data.Foldable (asum)
import Data.List (isInfixOf, maximumBy, sortOn)
import Data.List.Extra (trim)
import Data.Maybe (fromMaybe, mapMaybe, maybeToList)
import Data.Ord (comparing)
import GHC.Generics (Generic)
import Network.HTTP.Client (HttpException, responseTimeoutMicro)
import Network.HTTP.Simple
  ( getResponseBody,
    httpLBS,
    parseRequestThrow,
    setRequestHeader,
    setRequestResponseTimeout,
  )
import System.Environment (lookupEnv)
import System.Exit (die)

data Release = R
  { tag_name, name, html_url, published_at, created_at, body :: Maybe String,
    draft, prerelease :: Maybe Bool
  }
  deriving (Generic, FromJSON)

api :: String -> String -> String
api repo path = "https://api.github.com/repos/" <> repo <> path

latestTag :: String -> IO String
latestTag repo = do
  r <- fetchJson $ api repo "/releases/latest"
  maybe (die $ "Error: latest GitHub release for " <> repo <> " has no tag_name") pure $
    tag_name r >>= nonEmpty

-- | Highest-version stable release tag whose tag satisfies the predicate.
-- All release pages are scanned and the winner is chosen by numeric version,
-- so a low-minor LTS back-port published after a newer minor on the same major
-- (e.g. Prometheus' v3.5.x vs v3.12.x) does not win over the higher version.
latestTagWhere :: String -> (String -> Bool) -> IO String
latestTagWhere repo keep = do
  tags <- mapMaybe tagOf <$> stableReleasesWhere repo keep
  case tags of
    [] -> die $ "Error: no stable GitHub release for " <> repo <> " matched the requested version"
    ts -> pure $ maximumBy (comparing versionKey) ts

-- | Highest-version stable release tag after the current tag that satisfies
-- the predicate. If no post-current release is relevant, keep the current tag.
latestTagAfterWhere :: String -> String -> (String -> Bool) -> IO String
latestTagAfterWhere repo from keep = do
  tags <- mapMaybe tagOf . filter wanted <$> releasesAfter repo from
  case tags of
    [] -> pure from
    ts -> pure $ maximumBy (comparing versionKey) ts
  where
    lo = versionKey from
    wanted r =
      stable r
        && maybe False (\tag -> keep tag && versionKey tag > lo) (tagOf r)

changelog :: String -> String -> String -> IO String
changelog repo from to = changelogWhere repo from to (const True)

-- | Like 'changelog', but limited to stable releases whose tag satisfies the
-- predicate and whose version lies in @(from, to]@.
changelogWhere :: String -> String -> String -> (String -> Bool) -> IO String
changelogWhere repo from to keep =
  render repo from to <$> changelogReleasesWhere repo from to keep

downloadText :: String -> IO String
downloadText url = BL8.unpack <$> fetchBytes url

downloadFirstText :: [(String, String)] -> IO (String, String)
downloadFirstText candidates = go [] candidates
  where
    go errors = \case
      [] -> die $ unlines $ "Error: all GitHub downloads failed:" : reverse errors
      (label, url) : rest ->
        fetchBytesEither url >>= \case
          Right body -> pure (label, BL8.unpack body)
          Left err -> go (failure label url err : errors) rest

    failure label url err = "- " <> label <> " (" <> url <> "): " <> err

changelogReleasesWhere :: String -> String -> String -> (String -> Bool) -> IO [Release]
changelogReleasesWhere _ from to _ | from == to = pure []
changelogReleasesWhere repo from to keep = do
  let lo = versionKey from
      hi = versionKey to
  unless (hi > lo) $
    die $
      "Error: target release "
        <> show to
        <> " is not newer than current release "
        <> show from
        <> " for "
        <> repo

  releases <- releasesAfter repo from
  let tagged = mapMaybe (\r -> fmap (\tag -> (tag, r)) (tagOf r)) releases
      foundTarget = any ((== to) . fst) tagged
      wanted (tag, r) = stable r && keep tag && versionKey tag > lo && versionKey tag <= hi
  unless foundTarget $
    die $ "Error: Release tag " <> show to <> " was not found after " <> show from <> " in GitHub releases for " <> repo
  pure $ snd <$> filter wanted tagged

-- | Releases published after the current tag, newest first. This bounds
-- changelog fetching at the current version before any relevance filtering.
releasesAfter :: String -> String -> IO [Release]
releasesAfter repo from = go 1 []
  where
    go :: Int -> [Release] -> IO [Release]
    go page acc =
      fetchJson (api repo $ "/releases?per_page=100&page=" <> show page) >>= \case
        [] -> die $ "Error: Release tag " <> show from <> " was not found in GitHub releases for " <> repo
        rs -> scan page acc rs

    scan :: Int -> [Release] -> [Release] -> IO [Release]
    scan page acc = \case
      [] -> go (page + 1) acc
      r : rs
        | tagOf r == Just from -> pure $ reverse acc
        | otherwise -> scan page (r : acc) rs

allReleases :: String -> IO [Release]
allReleases repo = go 1 []
  where
    go :: Int -> [Release] -> IO [Release]
    go page acc =
      fetchJson (api repo $ "/releases?per_page=100&page=" <> show page) >>= \case
        [] -> pure acc
        rs -> go (page + 1) (acc <> rs)

fetchJson :: (FromJSON a) => String -> IO a
fetchJson url =
  fetchBytes url >>= either (die . ("Error: failed to decode GitHub API response: " <>)) pure . eitherDecode

fetchBytes :: String -> IO BL.ByteString
fetchBytes url = fetchBytesEither url >>= either (die . ("GitHub API/network error: " <>)) pure

fetchBytesEither :: String -> IO (Either String BL.ByteString)
fetchBytesEither url = (Right <$> action) `catch` \(e :: HttpException) -> pure $ Left $ displayException e
  where
    action = do
      token <- asum . map (>>= nonEmpty) <$> traverse lookupEnv ["GITHUB_TOKEN", "GH_TOKEN"]
      req <- parseRequestThrow url

      let auth = maybe id (\t -> setRequestHeader "Authorization" [BS.pack $ "Bearer " <> t]) token
          headers =
            setRequestResponseTimeout (responseTimeoutMicro 30000000)
              . setRequestHeader "Accept" ["application/vnd.github+json"]
              . setRequestHeader "User-Agent" ["update-all-docker-containers-haskell"]
              . setRequestHeader "X-GitHub-Api-Version" ["2022-11-28"]

      getResponseBody <$> httpLBS (auth $ headers req)

-- | All stable releases whose tag satisfies the predicate, across all pages.
stableReleasesWhere :: String -> (String -> Bool) -> IO [Release]
stableReleasesWhere repo keep = filter wanted <$> allReleases repo
  where
    wanted r = stable r && maybe False keep (tagOf r)

-- | A release's tag name if it is present and non-empty.
tagOf :: Release -> Maybe String
tagOf r = tag_name r >>= nonEmpty

-- | Numeric version components of a tag, e.g. @"v3.12.0" -> [3, 12, 0]@.
-- Compared lexicographically this orders releases by version.
versionKey :: String -> [Int]
versionKey = map read . words . map (\c -> if isDigit c then c else ' ')

stable :: Release -> Bool
stable R {..} =
  not (or $ fromMaybe False <$> [draft, prerelease])
    && all (maybe True $ not . unstable) [tag_name, name]

unstable :: String -> Bool
unstable x =
  any (`elem` bad) tokens || any (`isInfixOf` lower) ["pre-release", "pre release"]
  where
    lower = toLower <$> x
    tokens = words [if isAlphaNum c then c else ' ' | c <- lower]
    bad = ["alpha", "alfa", "beta", "rc", "preview", "nightly", "dev", "canary", "prerelease"]

render :: String -> String -> String -> [Release] -> String
render repo from to rs =
  unlines $
    [ "# Releases for `" <> repo <> "` since `" <> from <> "` through `" <> to <> "`",
      "",
      "Found " <> show (length sorted) <> " stable release(s) newer than `" <> from <> "` through `" <> to <> "`.",
      ""
    ]
      <> if null sorted then ["_No newer releases were found._", ""] else sorted >>= renderRelease
  where
    sorted = sortOn (fromMaybe "" . releaseDate) rs

renderRelease :: Release -> [String]
renderRelease r =
  [ "## " <> fromMaybe "Unnamed release" ((name r >>= nonEmpty) <|> (tag_name r >>= nonEmpty)),
    "",
    "- Tag: `" <> fromMaybe "unknown" (tag_name r) <> "`",
    "- Published: `" <> fromMaybe "unknown" (releaseDate r) <> "`"
  ]
    <> maybeToList (("- URL: " <>) <$> (html_url r >>= nonEmpty))
    <> ["", fromMaybe "_No description provided._" (trim <$> (body r >>= nonEmpty)), ""]

releaseDate :: Release -> Maybe String
releaseDate R {..} = published_at <|> created_at

nonEmpty :: String -> Maybe String
nonEmpty x = x <$ guard (not $ null $ trim x)
