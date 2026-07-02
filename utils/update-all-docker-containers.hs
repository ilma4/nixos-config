#!/usr/bin/env -S runhaskell -iutils

{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RecordWildCards #-}

import Control.Monad (guard, unless, when)
import Data.Char (isDigit)
import Data.Foldable (for_, traverse_)
import Data.List (isPrefixOf, stripPrefix)
import Data.List.Extra (splitOn)
import GitHub (changelogWhere, latestTag, latestTagAfterWhere)
import NixValue (Assign (..), assigns, select, writeAssign)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), die)
import System.FilePath (makeRelative, takeDirectory, (</>))
import System.IO (hPutStr, hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)
import Text.Read (readMaybe)

-- | A docker-compose service tracked in a Nix file. 'major', when set, pins the
-- service to that major version: updates stay within it and a newer major is
-- reported instead of applied.
data Service = S {name, file, repo, var, prefix :: String, dockerBuild :: Bool, major :: Maybe Int}

-- | Per-service result for the end-of-run overview; the last component holds
-- the latest tag and the pinned major it would cross, when that applies.
type Result = (String, Outcome, Maybe (String, Int))

data Outcome = Updated String String | UpToDate | BeyondPinned String

services :: [Service]
services =
  [ S "actual-budget" "hosts/nas/docker-services/actual-budget.nix" "actualbudget/actual" "actual-version" "" False Nothing,
    S "audiobookshelf" "hosts/nas/docker-services/audiobookshelf.nix" "advplyr/audiobookshelf" "version" "v" False Nothing,
    S "homer" "hosts/nas/dashboard.nix" "bastienwirtz/homer" "version" "" False Nothing,
    S "grafana" "hosts/nas/docker-services/grafana.nix" "grafana/grafana" "version" "v" True (Just 13),
    S "home-assistant" "hosts/nas/docker-services/home-assistant.nix" "home-assistant/core" "home-assistant-version" "" False Nothing,
    S "node-exporter" "hosts/nas/docker-services/node-exporter.nix" "prometheus/node_exporter" "node-exporter-version" "" False Nothing,
    S "stirling-pdf" "hosts/nas/docker-services/pdf-tools.nix" "Stirling-Tools/Stirling-PDF" "version" "v" False Nothing,
    S "pihole" "hosts/nas/docker-services/pihole.nix" "pi-hole/docker-pi-hole" "version" "" False Nothing,
    S "traefik" "hosts/nas/docker-services/traefik.nix" "traefik/traefik" "version" "" False (Just 3),
    S "alertmanager" "hosts/nas/prometheus/prometheus.nix" "prometheus/alertmanager" "alertmanagerVersion" "" False Nothing,
    S "prometheus" "hosts/nas/prometheus/prometheus.nix" "prometheus/prometheus" "version" "" False (Just 3)
  ]

main :: IO ()
main =
  getArgs >>= \case
    [] -> run True
    ["--apply"] -> run True
    ["--dry-run"] -> run False
    [x] | x `elem` ["-h", "--help"] -> putStr usage
    xs -> die $ "Error: unknown arguments: " <> unwords xs <> "\n" <> usage
  where
    run apply = do
      root <- takeDirectory . takeDirectory <$> makeAbsolute __FILE__
      results <- traverse (update root apply) services
      overview apply results
    usage =
      unlines
        [ "Usage: update-all-docker-containers.hs [--dry-run|--apply]",
          "",
          "Updates simple docker-compose service versions in Nix files.",
          "Apply is the default; pass --dry-run to preview changes without writing or committing.",
          "Applied updates are committed only when the service file was clean before that update."
        ]

update :: FilePath -> Bool -> Service -> IO Result
update root apply s@S {..} = do
  putStrLn $ "\n==> " <> name <> " (" <> repo <> ")"
  let path = root </> file
  doesFileExist path >>= (`unless` die ("Error: service Nix file does not exist: " <> file))

  text <- readFile path
  a@A {..} <- select var $ assigns text
  latest <- latestTag repo
  let current = versionToTag s aValue
      keep tag = all (\m -> majorOf tag == Just m) major
      exceeds tag m = any (> m) (majorOf tag)
      beyond = any (exceeds current) major
      newerMajor = major >>= \m -> (latest, m) <$ guard (exceeds latest m)
  targetTag <-
    if
      | beyond -> pure current
      | Just _ <- major -> latestTagAfterWhere repo current keep
      | otherwise -> pure latest
  target <- tagToVersion s targetTag

  putStr . unlines $
    [ "Service: " <> name,
      "Service file: " <> makeRelative root path,
      "GitHub repo: " <> repo,
      "Version variable: " <> var,
      "Current file version: " <> aValue,
      "Current GitHub release: " <> current,
      "Latest GitHub release: " <> latest
    ]
      <> ["Pinned major version: " <> show m | Just m <- [major]]
      <> [ "Target GitHub release: " <> targetTag,
           "Target file version: " <> target,
           "Mode: " <> if apply then "apply" else "dry-run"
         ]
  for_ newerMajor $ \(l, m) ->
    putStrLn $
      "\nNote: newer major release " <> l <> " is available but the service is pinned to major " <> show m
        <> "; not crossing major versions."

  outcome <-
    if
      | beyond -> do
          hPutStrLn stderr $
            "Warning: current version " <> current <> " for " <> name <> " is beyond its pinned major; leaving it unchanged."
          pure $ BeyondPinned current
      | current == targetTag -> UpToDate <$ putStrLn "Already up to date."
      | otherwise -> do
          clean <- if apply then null <$> git root ["status", "--porcelain", "--", file] else pure False
          putStrLn "\nChangelog:"
          putStr =<< changelogWhere repo current targetTag keep
          putStrLn ""
          writeAssign apply path text a target
          when (apply && aValue /= target) $
            if clean
              then do
                let msg = "update " <> name <> " " <> aValue <> " -> " <> target
                putStrLn $ "Committing: " <> msg
                putStr =<< git root ["commit", "--only", "-m", msg, "--", file]
              else
                hPutStrLn stderr $
                  "Warning: " <> file <> " was not clean before update started; not committing " <> name <> "."
          pure $ Updated aValue target
  pure (name, outcome, newerMajor)

overview :: Bool -> [Result] -> IO ()
overview apply results = do
  putStrLn $ "\n==> Overview (" <> (if apply then "apply" else "dry-run") <> ")"
  section
    (if apply then "Updated" else "Would update")
    [n <> ": " <> old <> " -> " <> new | (n, Updated old new, _) <- results]
  section "Kept as is (already up to date)" [n | (n, UpToDate, Nothing) <- results]
  section
    "New major version available (updated within pinned major only)"
    [pinned n nm | (n, Updated _ _, Just nm) <- results]
  section
    "Not updated (newer release crosses the pinned major)"
    [pinned n nm | (n, UpToDate, Just nm) <- results]
  section
    "Left unchanged (current version is beyond its pinned major)"
    [n <> ": " <> v | (n, BeyondPinned v, _) <- results]
  where
    section title items = unless (null items) $ putStrLn (title <> ":") >> traverse_ (putStrLn . ("  " <>)) items
    pinned n (latest, m) = n <> ": latest is " <> latest <> ", pinned to major " <> show m

-- | Run git in the repo root, passing stderr through; dies if git fails.
git :: FilePath -> [String] -> IO String
git root args = do
  (code, out, err) <- readProcessWithExitCode "git" ("-C" : root : args) ""
  unless (null err) $ hPutStr stderr err
  case code of
    ExitSuccess -> pure out
    ExitFailure n -> die $ "Error: git " <> unwords args <> " failed with exit code " <> show n

-- | The major version number of a tag, e.g. @"v3.7.5" -> Just 3@.
majorOf :: String -> Maybe Int
majorOf = readMaybe . takeWhile isDigit . dropWhile (not . isDigit)

versionToTag :: Service -> String -> String
versionToTag S {..} = addPrefix . if dockerBuild then dockerToSemVer else id
  where
    addPrefix v | prefix `isPrefixOf` v = v | otherwise = prefix <> v

tagToVersion :: Service -> String -> IO String
tagToVersion S {..} tag = maybe err check $ stripPrefix prefix tag
  where
    err = die $ "Error: latest release " <> tag <> " does not start with " <> prefix
    check v = do
      let x = if dockerBuild then semVerToDocker v else v
      when ('+' `elem` x) $ die $ "Error: target Docker image version contains '+': " <> x
      pure x

-- | Docker-build tags spell the semver @+build@ suffix with a @-@,
-- e.g. Grafana's image @12.1.1-security-01@ is release @12.1.1+security-01@.
dockerToSemVer, semVerToDocker :: String -> String
dockerToSemVer v
  | (nums, '-' : build) <- break (== '-') v,
    parts@[_, _, _] <- splitOn "." nums,
    all (not . null) parts,
    all (all isDigit) parts =
      nums <> "+" <> build
  | otherwise = v
semVerToDocker v = case break (== '+') v of
  (a, '+' : b) -> a <> "-" <> b
  _ -> v
