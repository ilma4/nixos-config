#!/usr/bin/env nix-shell
#!nix-shell -i "runghc -iutils" -p "haskellPackages.ghcWithPackages (p: with p; [ aeson bytestring directory extra filepath http-client http-conduit ])"

{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

import Control.Monad (unless, when)
import Data.Char (isDigit)
import Data.Foldable (traverse_)
import Data.List (intercalate, isPrefixOf, stripPrefix)
import Data.List.Extra (splitOn)
import GitHub (changelog, latestTag)
import NixValue (Assign (..), assigns, select, writeAssign)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), die, exitSuccess)
import System.FilePath (makeRelative, takeDirectory, (</>))
import System.IO (hPutStr, hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)

data Service = S {name, file, repo, var, prefix :: String, dockerBuild :: Bool}

services :: [Service]
services =
  [ S "actual-budget" "hosts/nas/docker-services/actual-budget.nix" "actualbudget/actual" "actual-version" "" False,
    S "audiobookshelf" "hosts/nas/docker-services/audiobookshelf.nix" "advplyr/audiobookshelf" "version" "v" False,
    S "homer" "hosts/nas/dashboard.nix" "bastienwirtz/homer" "version" "" False,
    S "grafana" "hosts/nas/docker-services/grafana.nix" "grafana/grafana" "version" "v" True,
    S "home-assistant" "hosts/nas/docker-services/home-assistant.nix" "home-assistant/core" "home-assistant-version" "" False,
    S "node-exporter" "hosts/nas/docker-services/node-exporter.nix" "prometheus/node_exporter" "node-exporter-version" "" False,
    S "stirling-pdf" "hosts/nas/docker-services/pdf-tools.nix" "Stirling-Tools/Stirling-PDF" "version" "v" False,
    S "pihole" "hosts/nas/docker-services/pihole.nix" "pi-hole/docker-pi-hole" "version" "" False,
    S "traefik" "hosts/nas/docker-services/traefik.nix" "traefik/traefik" "version" "" False,
    S "alertmanager" "hosts/nas/prometheus/prometheus.nix" "prometheus/alertmanager" "alertmanagerVersion" "" False,
    S "prometheus" "hosts/nas/prometheus/prometheus.nix" "prometheus/prometheus" "version" "" False
  ]

usage :: String
usage =
  unlines
    [ "Usage: update-all-docker-containers.hs [--dry-run|--apply]",
      "",
      "Updates simple docker-compose service versions in Nix files.",
      "Apply is the default; pass --dry-run to preview changes without writing or committing.",
      "Applied updates are committed only when the service file was clean before that update."
    ]

main :: IO ()
main = do
  apply <-
    getArgs >>= \case
      [] -> pure True
      ["--dry-run"] -> pure False
      ["--apply"] -> pure True
      [x] | x `elem` ["-h", "--help"] -> putStr usage >> exitSuccess
      xs -> die $ "Error: unknown arguments: " <> unwords xs <> "\n" <> usage

  root <- takeDirectory . takeDirectory <$> makeAbsolute __FILE__
  traverse_ (update root apply) services

update :: FilePath -> Bool -> Service -> IO ()
update root apply s@S {..} = do
  putStrLn $ "\n==> " <> name <> " (" <> repo <> ")"

  let path = root </> file
  exists <- doesFileExist path
  unless exists $ die $ "Error: service Nix file does not exist: " <> file

  text <- readFile path
  a@A {..} <- select var $ assigns text
  latest <- latestTag repo
  target <- tagToVersion s latest
  let current = versionToTag s aValue

  putStr . unlines $
    [ "Service: " <> name,
      "Service file: " <> makeRelative root path,
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
      cleanBefore <- if apply then gitFileClean root file else pure False
      putStrLn "\nChangelog:"
      putStr =<< changelog repo current latest
      putStrLn ""
      writeAssign apply path text a target
      when (apply && aValue /= target) $
        commitIfClean root file cleanBefore name aValue target

commitIfClean :: FilePath -> FilePath -> Bool -> String -> String -> String -> IO ()
commitIfClean root file cleanBefore serviceName oldVersion newVersion =
  if cleanBefore
    then do
      putStrLn $ "Committing: " <> message
      runGit root ["commit", "--only", "-m", message, "--", file]
    else
      hPutStrLn stderr $
        "Warning: " <> file <> " was not clean before update started; not committing " <> serviceName <> "."
  where
    message = "update " <> serviceName <> " " <> oldVersion <> " -> " <> newVersion

gitFileClean :: FilePath -> FilePath -> IO Bool
gitFileClean root file = do
  (code, out, err) <- readProcessWithExitCode "git" ["-C", root, "status", "--porcelain", "--", file] ""
  case code of
    ExitSuccess -> pure $ null out
    ExitFailure n -> die $ "Error: git status failed for " <> file <> " with exit code " <> show n <> ":\n" <> out <> err

runGit :: FilePath -> [String] -> IO ()
runGit root args = do
  (code, out, err) <- readProcessWithExitCode "git" ("-C" : root : args) ""
  putStr out
  unless (null err) $ hPutStr stderr err
  case code of
    ExitSuccess -> pure ()
    ExitFailure n -> die $ "Error: git " <> unwords args <> " failed with exit code " <> show n

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
