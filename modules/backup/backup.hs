{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}

import Control.Monad (filterM, void)
import Data.Aeson (FromJSON, Result (Error, Success), Value, fromJSON, throwDecode)
import Data.ByteString.Lazy qualified as Lazy
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Foldable (for_)
import Data.List ((\\))
import Data.Map.Strict qualified as Map
import GHC.Base (when)
import GHC.Generics (Generic)
import GHC.IO.Exception (ExitCode (ExitSuccess))
import System.Environment
import System.Exit (ExitCode (ExitFailure))
import System.Process (readProcessWithExitCode)

type PasswordFile = String

data Repo = Repo {location :: String, passwordFile :: PasswordFile, oldPasswordFile :: Maybe PasswordFile, extraArgs :: [String]}
  deriving (Show, Generic, Eq)

data BackupConfig = BackupConfig
  { localRepo :: Repo,
    remoteRepos :: [Repo],
    paths :: [String],
    excludes :: [String],
    keepWithin :: Maybe String
  }
  deriving (Show, Generic)

instance FromJSON Repo

instance FromJSON BackupConfig

withOldPassword :: Repo -> Maybe Repo
withOldPassword Repo {..} = fmap (\oldPassword -> Repo location oldPassword Nothing extraArgs) oldPasswordFile

runRestic :: Repo -> [String] -> IO (ExitCode, String, String)
runRestic Repo {..} args = readProcessWithExitCode "restic" (["-r", location, "--password-file", passwordFile] ++ extraArgs ++ args) ""

runResticThrowing :: Repo -> [String] -> IO String
runResticThrowing repo args = do
  (exitCode, stdout, _) <- runRestic repo args
  when (exitCode /= ExitSuccess) (error $ "failed to run " ++ show repo ++ show args)
  return stdout

exists :: Repo -> IO Bool
exists repo = do
  (exitCode, _, _) <- runRestic repo ["cat", "config"]
  return (exitCode == ExitSuccess)

fromArgs :: Repo -> [String]
fromArgs Repo {..} = ["--from-repo", location, "--from-password-file", passwordFile] ++ extraArgs

readRepoChunker :: Repo -> IO String
readRepoChunker repo = do
  (_, stdout, _) <- runRestic repo ["--json", "cat", "config"]
  dict <- throwDecode (L8.pack stdout) :: IO (Map.Map String Value)
  case fromJSON $ dict Map.! "chunker_polynomial" of
    Success chunker -> return chunker
    Error err -> error ("invalid chunker_polynomial in restic config: " ++ err)

rotateKey :: Repo -> IO ()
rotateKey repo@Repo {..} = do
  (exitCode, _, _) <- runRestic repo ["cat", "config"]
  case (exitCode, withOldPassword repo) of
    (ExitSuccess, _) -> return ()
    (ExitFailure 12, Nothing) -> error $ "no old password in repo " ++ show repo
    (ExitFailure 12, Just oldPasswordRepo) ->
      void $ runResticThrowing oldPasswordRepo ["key", "passwd", "--new-password-file", passwordFile]
    (ExitFailure _, _) -> error "unexpected error"

initReposCommand :: String -> IO ()
initReposCommand file = do
  allRepos <- Lazy.readFile file >>= throwDecode :: IO [Repo]
  existingRepos <- filterM exists allRepos
  case (allRepos, existingRepos) of
    ([], _) -> return () -- no repos, no init
    (_, []) -> error "Can't init repo because no repo exists/accessible"
    (_, fromRepo : _) -> do
      let args = "init" : "--copy-chunker-params" : fromArgs fromRepo
      mapM_ (`runResticThrowing` args) (allRepos \\ existingRepos)

rotateKeysCommand :: String -> IO ()
rotateKeysCommand file = do
  repos <- Lazy.readFile file >>= throwDecode :: IO [Repo]
  mapM_ rotateKey repos

requireChunckerMatching :: String -> Repo -> IO ()
requireChunckerMatching chunker repo = do
  repoChunker <- readRepoChunker repo
  when (chunker /= repoChunker) (error "chunkers are not same")

runBackupCommand :: String -> IO ()
runBackupCommand file = do
  BackupConfig {..} <- Lazy.readFile file >>= throwDecode :: IO BackupConfig
  let backupArgs = ["backup"] ++ concatMap (\path -> ["--exclude", path]) excludes ++ paths
  (exitCode, _, stderr) <- runRestic localRepo backupArgs
  when (exitCode /= ExitSuccess && exitCode /= ExitFailure 3) (error $ "error while running backup\n" ++ stderr)
  when (exitCode == ExitFailure 3) (putStrLn $ "backup can't read some paths:\n" ++ stderr)
  putStrLn "backup successfully made"

  localChunker <- readRepoChunker localRepo
  for_ remoteRepos (requireChunckerMatching localChunker)
  for_ remoteRepos $ \remoteRepo -> do
    void $ runResticThrowing remoteRepo ("copy" : fromArgs localRepo)
    putStrLn $ "backup successfully copied to remote repo " ++ location remoteRepo
  when (not (null remoteRepos)) (putStrLn "backup successfully copied to all remote repos")
  for_ keepWithin $ \interval -> do
    void $ runResticThrowing localRepo ["forget", "--prune", "--keep-within", interval]
    putStrLn "backup successfully pruned"

main :: IO ()
main = do
  (command : file : _) <- getArgs
  case command of
    "init-repos" -> initReposCommand file
    "rotate-keys" -> rotateKeysCommand file
    "run-backup" -> runBackupCommand file
    _ -> error ("unknown command " ++ command)
