{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module GitHub
  ( latestTag,
    changelog,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (catch, displayException)
import Control.Monad (guard)
import Data.Aeson (FromJSON, eitherDecode)
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAlphaNum, toLower)
import Data.Foldable (asum)
import Data.List (isInfixOf, sortOn)
import Data.List.Extra (trim)
import Data.Maybe (fromMaybe, maybeToList)
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

changelog :: String -> String -> String -> IO String
changelog repo from to = render repo from to <$> releasesBetween repo from to

releasesBetween :: String -> String -> String -> IO [Release]
releasesBetween _ from to | from == to = pure []
releasesBetween repo from to = go 1 False []
  where
    go :: Int -> Bool -> [Release] -> IO [Release]
    go page seen acc =
      fetchJson (api repo $ "/releases?per_page=100&page=" <> show page) >>= \case
        [] -> die $ "Error: Release tag " <> show from <> " was not found in GitHub releases for " <> repo
        rs -> scan page seen acc rs

    scan :: Int -> Bool -> [Release] -> [Release] -> IO [Release]
    scan page seen acc = \case
      [] -> go (page + 1) seen acc
      r : rs
        | tag_name r == Just from ->
            if seen then pure acc else die $ "Error: Release tag " <> show to <> " was not found before " <> show from
        | tag_name r == Just to || seen ->
            scan page True (if stable r then r : acc else acc) rs
        | otherwise -> scan page seen acc rs

fetchJson :: (FromJSON a) => String -> IO a
fetchJson url =
  fetchBytes url >>= either (die . ("Error: failed to decode GitHub API response: " <>)) pure . eitherDecode

fetchBytes :: String -> IO BL.ByteString
fetchBytes url =
  action `catch` \(e :: HttpException) ->
    die $ "GitHub API/network error: " <> displayException e
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
