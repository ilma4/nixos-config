#!/usr/bin/env nix-shell
#!nix-shell -i "runghc -iutils" -p "haskellPackages.ghcWithPackages (p: with p; [ aeson bytestring containers directory extra filepath http-client http-conduit text yaml ])"

{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

import Control.Monad (forM_, unless, when)
import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Char (toLower)
import Data.List (intercalate, isInfixOf, isPrefixOf, (\\))
import Data.List.Extra (trim)
import Data.Map.Strict qualified as M
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Yaml qualified as Y
import GitHub (changelog, downloadFirstText, latestTag)
import NixValue (Assign (..), assigns, select, writeAssign)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (die, exitFailure, exitSuccess)
import System.FilePath (makeRelative, takeDirectory, (</>))

repo, versionVar :: String
repo = "immich-app/immich"
versionVar = "immich-version"

type Images = M.Map String String

type ImageChange = (String, String, String) -- service, old, new

usage :: String
usage =
  unlines
    [ "Usage: update-immich.hs [--dry-run|--apply]",
      "",
      "Updates Immich docker-compose image pins and immich-version in immich.nix.",
      "Apply is the default; pass --dry-run to preview changes without writing."
    ]

main :: IO ()
main = do
  apply <- parseArgs

  root <- takeDirectory . takeDirectory <$> makeAbsolute __FILE__
  let relNix = "hosts/nas/docker-services/immich/immich.nix"
      relCompose = "hosts/nas/docker-services/immich/docker-compose.yml"
      relEnv = "hosts/nas/docker-services/immich/.env"
      nixFile = root </> relNix
      composeFile = root </> relCompose
      envFile = root </> relEnv

  mapM_ requireFile [nixFile, composeFile, envFile]

  nixText <- readFile nixFile
  versionAssign@A {aValue = current} <- select versionVar $ assigns nixText
  latest <- latestTag repo
  mapM_ validateNixString [current, latest]

  putStr . unlines $
    [ "Service: Immich",
      "GitHub repo: " <> repo,
      "Version variable: " <> versionVar,
      "Nix file: " <> makeRelative root nixFile,
      "Compose file: " <> makeRelative root composeFile,
      "Current version: " <> current,
      "Latest release: " <> latest,
      "Mode: " <> if apply then "apply" else "dry-run"
    ]

  when (current /= latest) $ do
    notes <- changelog repo current latest
    putStrLn "\nChangelog:"
    putStr notes
    gateBreakingChanges notes

  (assetName, upstreamText) <- downloadCompose latest
  putStrLn $ "\nDownloaded upstream " <> assetName <> " for " <> latest <> "."

  localYaml <- readYaml composeFile
  upstreamYaml <- parseYaml assetName $ TE.encodeUtf8 $ T.pack upstreamText

  changes <- planComposeChanges (composeImages localYaml) (composeImages upstreamYaml)
  reportComposeChanges apply composeFile changes

  envText <- readFile envFile
  let (updatedEnv, envChanged) = removeDuplicatedEnvVersion envText
  reportEnvMigration apply envFile envChanged

  when apply $ do
    unless (null changes) $
      BS.writeFile composeFile $
        Y.encode $
          replaceImages changes localYaml

    when envChanged $
      writeFile envFile updatedEnv

  writeAssign apply nixFile nixText versionAssign latest

parseArgs :: IO Bool
parseArgs =
  getArgs >>= \case
    [] -> pure True
    ["--dry-run"] -> pure False
    ["--apply"] -> pure True
    [x] | x `elem` ["-h", "--help"] -> putStr usage >> exitSuccess
    xs -> die $ "Error: unknown arguments: " <> unwords xs <> "\n" <> usage

requireFile :: FilePath -> IO ()
requireFile path =
  doesFileExist path
    >>= flip
      unless
      (die $ "Error: required file does not exist: " <> path)

validateNixString :: String -> IO ()
validateNixString v
  | null v = die "Error: version must not be empty"
  | any (`elem` ['"', '\\', '\n', '\r']) v =
      die $ "Error: version contains characters this script will not quote safely: " <> show v
  | otherwise = pure ()

downloadCompose :: String -> IO (String, String)
downloadCompose tag =
  downloadFirstText
    [ (name, "https://github.com/" <> repo <> "/releases/download/" <> tag <> "/" <> name)
    | name <- ["docker-compose.yml", "docker-compose.yaml"]
    ]

readYaml :: FilePath -> IO Value
readYaml path = BS.readFile path >>= parseYaml path

parseYaml :: FilePath -> BS.ByteString -> IO Value
parseYaml path bs =
  either (die . msg) pure $ Y.decodeEither' bs
  where
    msg e = "Error: failed to parse YAML " <> path <> ": " <> Y.prettyPrintParseException e

composeImages :: Value -> Images
composeImages (Object root)
  | Just (Object services) <- KM.lookup "services" root =
      M.fromList $ mapMaybe serviceImage $ KM.toList services
  where
    serviceImage (name, Object svc)
      | Just (String image) <- KM.lookup "image" svc =
          Just (Key.toString name, T.unpack image)
    serviceImage _ = Nothing
composeImages _ = M.empty

planComposeChanges :: Images -> Images -> IO [ImageChange]
planComposeChanges local upstream = do
  let localNames = M.keys local
      upstreamNames = M.keys upstream

  when (null upstream) $ die "Error: no image entries found in upstream Immich compose file"
  when (null local) $ die "Error: no image entries found in local Immich compose file"

  refuse "upstream compose contains image services missing locally" $ upstreamNames \\ localNames
  refuse "local compose contains image services missing upstream" $ localNames \\ upstreamNames

  pure
    [ (name, old, new)
    | (name, old) <- M.toList local,
      Just new <- [M.lookup name upstream],
      old /= new
    ]
  where
    refuse msg xs =
      unless (null xs) $
        die $
          "Error: "
            <> msg
            <> ": "
            <> intercalate ", " xs
            <> ". Refusing to silently add/remove services; review Immich compose changes manually."

replaceImages :: [ImageChange] -> Value -> Value
replaceImages changes =
  replaceImages' $ M.fromList [(name, new) | (name, _, new) <- changes]

replaceImages' :: Images -> Value -> Value
replaceImages' newImages (Object root) =
  Object $ adjustKey "services" updateServices root
  where
    updateServices (Object services) =
      Object $ KM.mapWithKey updateService services
    updateServices x = x

    updateService name (Object svc)
      | Just image <- M.lookup (Key.toString name) newImages =
          Object $ KM.insert "image" (String $ T.pack image) svc
    updateService _ x = x
replaceImages' _ value = value

adjustKey :: Key.Key -> (a -> a) -> KM.KeyMap a -> KM.KeyMap a
adjustKey key f values =
  case KM.lookup key values of
    Just value -> KM.insert key (f value) values
    Nothing -> values

reportComposeChanges :: Bool -> FilePath -> [ImageChange] -> IO ()
reportComposeChanges apply composeFile changes =
  if null changes
    then putStrLn $ composeFile <> ": compose image pins are already aligned with upstream."
    else do
      putStrLn "\nCompose image changes:"
      forM_ changes $ \(name, old, new) ->
        putStrLn $ "- " <> name <> ": " <> old <> " -> " <> new
      putStrLn $ action <> " " <> composeFile <> ": " <> show (length changes) <> " image pin(s)"
  where
    action = if apply then "Updated" else "Would update"

removeDuplicatedEnvVersion :: String -> (String, Bool)
removeDuplicatedEnvVersion text = (unlines updated, original /= updated)
  where
    original = lines text
    updated = map replace original

    replace line
      | "IMMICH_VERSION=" `isPrefixOf` trim line =
          "# IMMICH_VERSION is managed by immich-version in immich.nix."
      | otherwise = line

reportEnvMigration :: Bool -> FilePath -> Bool -> IO ()
reportEnvMigration apply envFile changed =
  putStrLn $
    if changed
      then action <> " " <> envFile <> ": remove duplicated IMMICH_VERSION from env file"
      else envFile <> ": no duplicated IMMICH_VERSION entry found."
  where
    action = if apply then "Updated" else "Would update"

gateBreakingChanges :: String -> IO ()
gateBreakingChanges notes =
  case filter suspicious $ splitMarkdownSections notes of
    [] -> putStrLn "\nNo obvious breaking/migration/manual-action sections detected in release notes."
    xs -> do
      putStrLn "\nPotential breaking changes or migration/manual-action notes were detected."
      putStrLn "No files were written. Review the excerpts below before applying the update.\n"

      forM_ (zip [1 :: Int ..] $ take 10 xs) $ \(n, section) -> do
        putStrLn $ "--- Potential issue " <> show n <> " ---"
        putStrLn $ trim $ unlines $ take 80 $ lines section

      when (length xs > 10) $
        putStrLn $
          "\n... " <> show (length xs - 10) <> " additional suspicious section(s) omitted."

      exitFailure

suspicious :: String -> Bool
suspicious section =
  let lower = unwords . words $ map toLower section
   in not (any (`isInfixOf` lower) nonBreakingPhrases)
        && any (`isInfixOf` lower) breakingKeywords

breakingKeywords, nonBreakingPhrases :: [String]
breakingKeywords =
  [ "breaking change",
    "breaking changes",
    "breaking:",
    "migration guide",
    "manual migration",
    "manual action",
    "manual step",
    "manual intervention",
    "action required",
    "required action",
    "requires manual",
    "database migration",
    "storage template migration",
    "removed support",
    "remove support",
    "before upgrading",
    "after upgrading",
    "must update",
    "must be updated",
    "cannot upgrade",
    "migrating from",
    "migrate from"
  ]
nonBreakingPhrases =
  [ "no breaking changes",
    "no breaking change",
    "without breaking changes",
    "does not contain breaking changes",
    "does not include breaking changes",
    "nothing is currently planned that requires user intervention",
    "nothing currently planned that requires user intervention"
  ]

splitMarkdownSections :: String -> [String]
splitMarkdownSections =
  reverse . map (unlines . reverse) . foldl step [] . lines
  where
    step [] line = [[line]]
    step acc@(section : rest) line
      | "#" `isPrefixOf` trim line && not (null section) = [line] : acc
      | otherwise = (line : section) : rest
