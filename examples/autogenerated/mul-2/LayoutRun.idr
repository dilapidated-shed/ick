module LayoutRun
import Data.List
import Data.So
import System
import System.File
%default covering

save : String -> String -> IO ()
save path contents = do
  Right () <- writeFile path contents | _ => exitWith (ExitFailure 8)
  pure ()

finish : Int -> IO ()
finish 0 = pure ()
finish status =
  let retained = if status>0 && status<256 then status else 8 in
  case choose (retained/=0) of
    Left nonzero => exitWith (ExitFailure retained @{nonzero})
    Right _ => exitWith (ExitFailure 8)

one : String -> String -> String -> String -> String -> IO Int
one kind candidate oracle gate stem = do
  (symbols, symbolStatus) <- System.Escaped.run ["nm","-D","--undefined-only",candidate]
  save (stem ++ ".symbols") symbols
  save (stem ++ ".symbols.status") (show symbolStatus ++ "\n")
  if symbolStatus/=0 then pure symbolStatus else do
    -- Existing process seam: escape every supplied argument, retain stderr as a file.
    (actual, candidateStatus) <- System.run (escapeCmd [candidate] ++ " 2> " ++ escapeArg (stem ++ ".stderr"))
    save (stem ++ ".stdout.tsv") actual
    save (stem ++ ".candidate.status") (show candidateStatus ++ "\n")
    (message, gateStatus) <- System.Escaped.run [gate,kind,oracle,stem ++ ".stdout.tsv",stem ++ ".symbols"]
    save (stem ++ ".gate.stdout") message
    save (stem ++ ".gate.status") (show gateStatus ++ "\n")
    putStr message
    pure (if candidateStatus/=0 then candidateStatus else gateStatus)

negative : String -> String -> String -> String -> String -> String -> IO Bool
negative self kind candidate oracle gate stem = do
  (message, outerStatus) <- System.Escaped.run [self,"one",kind,candidate,oracle,gate,stem]
  save (stem ++ ".outer.stdout") message
  save (stem ++ ".outer.status") (show outerStatus ++ "\n")
  Right candidateText <- readFile (stem ++ ".candidate.status") | _ => pure False
  Right gateText <- readFile (stem ++ ".gate.status") | _ => pure False
  let detected = outerStatus/=0 && (candidateText/="0\n" || gateText/="0\n")
  putStrLn ((if detected then "PASS detected " else "FAIL undetected ") ++ candidate)
  pure detected

main : IO ()
main = do
  args <- getArgs
  case args of
    [_,"one",kind,candidate,oracle,gate,stem] => finish !(one kind candidate oracle gate stem)
    [self,"mutants",directory,gate] => do
      let frameCases = ["endpoint-sign","source-rank","auxiliary-frame"]
      let packedCases = ["inverse-order","omitted-correction"]
      frameResults <- traverse (\name => negative self "frames" (directory ++ "/" ++ name)
        (directory ++ "/frames-v1.tsv") gate (directory ++ "/" ++ name)) frameCases
      packedResults <- traverse (\name => negative self "packed" (directory ++ "/" ++ name)
        (directory ++ "/packed-v1.tsv") gate (directory ++ "/" ++ name)) packedCases
      if all id (frameResults ++ packedResults) then pure () else exitWith (ExitFailure 8)
    _ => exitWith (ExitFailure 8)
