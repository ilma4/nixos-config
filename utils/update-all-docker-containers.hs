#!/usr/bin/env nix-shell
#!nix-shell -i "runghc -iutils" -p "haskellPackages.ghcWithPackages (p: with p; [ aeson bytestring directory extra filepath http-client http-conduit ])"

{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

import Control.Monad (guard, unless, when)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, isSpace)
import Data.Foldable (traverse_)
import Data.List (intercalate, isPrefixOf, stripPrefix)
import Data.List.Extra (splitOn)
import Data.Maybe (listToMaybe, mapMaybe)
import GitHub (changelog, latestTag)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (die, exitSuccess)
import System.FilePath ((</>), makeRelative, takeDirectory)

data Service = S {file, repo, var, prefix :: String, dockerBuild :: Bool}

services :: [Service]
services =
  [ S "hosts/nas/docker-services/actual-budget.nix" "actualbudget/actual" "actual-version" "" False,
    S "hosts/nas/docker-services/audiobookshelf.nix" "advplyr/audiobookshelf" "version" "v" False,
    S "hosts/nas/docker-services/grafana.nix" "grafana/grafana" "version" "v" True,
    S "hosts/nas/docker-services/home-assistant.nix" "home-assistant/core" "home-assistant-version" "" False,
    S "hosts/nas/docker-services/node-exporter.nix" "prometheus/node_exporter" "node-exporter-version" "" False,
    S "hosts/nas/docker-services/pdf-tools.nix" "Stirling-Tools/Stirling-PDF" "version" "v" False,
    S "hosts/nas/docker-services/pihole.nix" "pi-hole/docker-pi-hole" "version" "" False,
    S "hosts/nas/docker-services/traefik.nix" "traefik/traefik" "version" "" False,
    S "hosts/nas/prometheus/prometheus.nix" "prometheus/alertmanager" "alertmanagerVersion" "" False,
    S "hosts/nas/prometheus/prometheus.nix" "prometheus/prometheus" "version" "" False
  ]

usage :: String
usage =
  unlines
    [ "Usage: update-all-docker-containers.hs [--dry-run|--apply]",
      "",
      "Updates simple docker-compose service versions in Nix files.",
      "Dry-run is the default; pass --apply to write changes."
    ]

main :: IO ()
main = do
  apply <-
    getArgs >>= \case
      [] -> pure False
      ["--dry-run"] -> pure False
      ["--apply"] -> pure True
      [x] | x `elem` ["-h", "--help"] -> putStr usage >> exitSuccess
      xs -> die $ "Error: unknown arguments: " <> unwords xs <> "\n" <> usage

  root <- takeDirectory . takeDirectory <$> makeAbsolute __FILE__
  traverse_ (update root apply) services

update :: FilePath -> Bool -> Service -> IO ()
update root apply s@S {..} = do
  putStrLn $ "\n==> " <> file <> " (" <> repo <> ")"

  let path = root </> file
  exists <- doesFileExist path
  unless exists $ die $ "Error: service Nix file does not exist: " <> file

  text <- readFile path
  a@A {..} <- select var $ assigns text
  latest <- latestTag repo
  target <- tagToVersion s latest
  let current = versionToTag s aValue

  putStr . unlines $
    [ "Service file: " <> makeRelative root path,
      "GitHub repo: " <> repo,
      "Version variable: " <> var,
      "Current file version: " <> aValue,
      "Current GitHub release: " <> current,
      "Latest GitHub release: " <> latest,
      "Target file version: " <> target,
      "Mode: " <> if apply then "apply" else "dry-run"
    ]

  if current == latest
    then putStrLn "Already up to date."
    else do
      putStrLn "\nChangelog:"
      putStr =<< changelog repo current latest
      putStrLn ""
      writeAssign apply path text a target

versionToTag :: Service -> String -> String
versionToTag S {..} = addPrefix . if dockerBuild then dockerToSemVer else id
  where
    addPrefix v | prefix `isPrefixOf` v = v | otherwise = prefix <> v

tagToVersion :: Service -> String -> IO String
tagToVersion S {..} tag = maybe err check $ stripPrefix prefix tag
  where
    err = die $ "Error: latest release " <> tag <> " does not start with " <> prefix
    check v = do
      let x = if dockerBuild then replaceFirst '+' '-' v else v
      when ('+' `elem` x) $ die $ "Error: target Docker image version contains '+': " <> x
      pure x

dockerToSemVer :: String -> String
dockerToSemVer v
  | (nums, '-' : build) <- break (== '-') v,
    parts@[_, _, _] <- splitOn "." nums,
    all (not . null) parts,
    all (all isDigit) parts =
      intercalate "." parts <> "+" <> build
  | otherwise = v

replaceFirst :: (Eq a) => a -> a -> [a] -> [a]
replaceFirst old new xs = case break (== old) xs of
  (a, _ : b) -> a ++ new : b
  _ -> xs

data Assign = A
  { lineNo :: Int,
    indent, aName, aValue, trailing :: String
  }

assigns :: String -> [Assign]
assigns = mapMaybe parseAssign . zip [0 ..] . lines

select :: String -> [Assign] -> IO Assign
select name =
  \case
    [x] -> pure x
    [] -> die $ "Error: Version variable " <> show name <> " was not found"
    _ -> die $ "Error: Version variable " <> show name <> " is not unique"
    . filter ((== name) . aName)

parseAssign :: (Int, String) -> Maybe Assign
parseAssign (lineNo, raw) = do
  let (indent, s) = span isSpace raw
      (aName, rest) = span isNameChar s
  guard $ maybe False isNameStart $ listToMaybe aName
  q <- stripPrefix "=" $ dropWhile isSpace rest
  x <- stripPrefix "\"" $ dropWhile isSpace q
  let (aValue, after) = break (== '"') x
  trailing <- stripPrefix "\";" after
  pure A {..}

isNameStart, isNameChar :: Char -> Bool
isNameStart c = isAsciiLower c || isAsciiUpper c || c == '_'
isNameChar c = isNameStart c || isDigit c || c == '-'

writeAssign :: Bool -> FilePath -> String -> Assign -> String -> IO ()
writeAssign apply path text A {..} v
  | null v = die "Error: Version must not be empty"
  | any (`elem` ['"', '\\', '\n', '\r']) v = die "Error: Version contains characters this script will not quote"
  | aValue == v = putStrLn $ path <> ": " <> aName <> " is already " <> v
  | otherwise = do
      when apply $ writeFile path $ replaceLine lineNo line text
      putStrLn $ action <> " " <> path <> ": " <> aName <> " " <> aValue <> " -> " <> v
  where
    line = indent <> aName <> " = \"" <> v <> "\";" <> trailing
    action = if apply then "Updated" else "Would update"

replaceLine :: Int -> String -> String -> String
replaceLine n new = unlines . zipWith pick [0 ..] . lines
  where
    pick i old | i == n = new | otherwise = old
