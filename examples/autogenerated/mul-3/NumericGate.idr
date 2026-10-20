module NumericGate
import Data.List
import Data.Maybe
import Data.String
import System
import System.File
%default covering

allowed : List String
allowed = ["calloc","free","memcmp","memcpy","memmove","memset","printf","sprintf","puts",
           "strcmp","putchar","putc","fprintf","fputs","fwrite","ferror","fflush","stderr","stdout",
           "clock","getrusage","__libc_start_main","__cxa_finalize","__gmon_start__",
           "_ITM_deregisterTMCloneTable","_ITM_registerTMCloneTable"]
symbol : String -> String
symbol line = pack (takeWhile (/= '@') (unpack (fromMaybe "" (last' (words line)))))
provenance : String -> Bool
provenance contents =
  let names=map symbol (filter (/= "") (lines contents)) in
  not (null names) && elem "calloc" names && elem "__libc_start_main" names && all (`elem` allowed) names
field : String -> String -> Bool
field wanted line = elem wanted (words line)
costs : String -> String -> Bool
costs kind contents = case kind of
  "transform" =>
    let samples=filter (\line => isPrefixOf "forward\t" line || isPrefixOf "opposite\t" line) (lines contents) in
    length samples==180 && all (\line =>
      field (if field "profile=0" line || field "profile=4" line then "motif_calls=16" else if field "profile=3" line then "motif_calls=48" else "motif_calls=32") line &&
      field "short_calls=0" line &&
      field (if field "profile=0" line || field "profile=4" line then "rounds=1" else if field "profile=3" line then "rounds=3" else "rounds=2") line) samples
  "convolution" =>
    let samples=filter (isPrefixOf "convolution\t") (lines contents) in
    length samples==15 && all (\line =>
      field (if field "profile=0" line || field "profile=4" line then "motif_calls=48" else if field "profile=3" line then "motif_calls=144" else "motif_calls=96") line &&
      field (if field "profile=0" line then "short_calls=16" else if field "profile=1" line || field "profile=4" line then "short_calls=32" else if field "profile=2" line then "short_calls=64" else "short_calls=128") line) samples
  "phase" =>
    let samples=filter (isPrefixOf "phase-model\t") (lines contents) in
    length samples==41 && all (\line => field "frame_calls=16" line && field "prepared_matrix_entries=100532224" line && field "guards=32,32" line) samples
  _ => True
main : IO ()
main = do
  [_,kind,expectedPath,actualPath,symbolsPath,costPath] <- getArgs | _ => exitWith (ExitFailure 9)
  Right expected <- readFile expectedPath | _ => exitWith (ExitFailure 9)
  Right actual <- readFile actualPath | _ => exitWith (ExitFailure 9)
  Right symbols <- readFile symbolsPath | _ => exitWith (ExitFailure 9)
  Right measured <- readFile costPath | _ => exitWith (ExitFailure 9)
  let count=case kind of
        "child" => 706
        "transform" => 18240
        "convolution" => 7584
        "phase" => 5208
        "packed" => 1824
        "refusals" => 29
        _ => 0
  if count>0 && expected==actual && length (lines actual)==count && provenance symbols && costs kind measured
    then putStrLn ("PASS " ++ kind ++ " exact bytes, execution receipts and candidate-only linkage")
    else do putStrLn ("FAIL " ++ kind ++ " bytes, count, execution receipts or provenance")
            exitWith (ExitFailure 9)
