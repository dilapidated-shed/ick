module LayoutGate
import Data.List
import Data.Maybe
import Data.String
import System
import System.File
%default covering

allowed : List String
allowed = ["calloc","free","memcmp","memcpy","memmove","memset","printf","sprintf",
           "strcmp","putchar","putc","fprintf","fputs","fwrite","ferror","stderr",
           "stdout","__libc_start_main","__cxa_finalize","__gmon_start__",
           "_ITM_deregisterTMCloneTable","_ITM_registerTMCloneTable"]

symbol : String -> String
symbol line = pack (takeWhile (/= '@') (unpack (fromMaybe "" (last' (words line)))))

provenance : String -> Bool
provenance text =
  let names = map symbol (filter (/= "") (lines text)) in
  not (null names) && elem "calloc" names && elem "__libc_start_main" names && all (`elem` allowed) names

main : IO ()
main = do
  [_, kind, expectedPath, actualPath, symbolsPath] <- getArgs | _ => exitWith (ExitFailure 9)
  Right expected <- readFile expectedPath | _ => exitWith (ExitFailure 9)
  Right actual <- readFile actualPath | _ => exitWith (ExitFailure 9)
  Right symbols <- readFile symbolsPath | _ => exitWith (ExitFailure 9)
  let count = if kind=="frames" then 10931 else if kind=="packed" then 123904 else 0
  if count>0 && expected==actual && length (lines actual)==count && provenance symbols
    then putStrLn ("PASS " ++ kind ++ " exact bytes and candidate-only linkage")
    else do putStrLn ("FAIL " ++ kind ++ " bytes, count, or candidate-only linkage")
            exitWith (ExitFailure 9)
