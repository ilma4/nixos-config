{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

module NixValue
  ( Assign (..),
    assigns,
    select,
    writeAssign,
  )
where

import Control.Monad (guard, when)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, isSpace)
import Data.List (stripPrefix)
import Data.Maybe (listToMaybe, mapMaybe)
import System.Exit (die)

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
