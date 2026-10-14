module Run
import Data.List
import Data.Maybe
import Data.String
import Data.So
import System
import System.File
%default covering

save : String -> String -> IO ()
save path contents = do
  Right () <- writeFile path contents | Left error => do
    putStrLn ("FAIL cannot retain " ++ path ++ ": " ++ show error)
    exitWith (ExitFailure 8)
  pure ()

finish : Int -> IO ()
finish 0 = pure ()
finish status =
  let exit_status = if status>0 && status<256 then status else 8 in
  case choose (not (exit_status==0)) of
    Left nonzero => exitWith (ExitFailure exit_status @{nonzero})
    Right _ => exitWith (ExitFailure 8)

one : String -> String -> String -> String -> IO Int
one candidate oracle gate artifact_stem = do
  _ <- setEnv "SCALAR_ORACLE_OUTPUT" oracle True
  (symbols, symbolStatus) <- System.Escaped.run ["nm","-D","--undefined-only",candidate]
  save (artifact_stem ++ ".symbols") symbols
  save (artifact_stem ++ ".symbols.status") (show symbolStatus ++ "\n")
  if symbolStatus/=0 then pure symbolStatus else do
    (actual, candidateStatus) <- System.Escaped.run [candidate]
    save (artifact_stem ++ ".stdout.tsv") actual
    save (artifact_stem ++ ".candidate.status") (show candidateStatus ++ "\n")
    (message, gateStatus) <- System.Escaped.run [gate,oracle,artifact_stem ++ ".stdout.tsv",artifact_stem ++ ".symbols"]
    save (artifact_stem ++ ".gate.stdout") message
    save (artifact_stem ++ ".gate.status") (show gateStatus ++ "\n")
    putStr message
    pure (if candidateStatus/=0 then candidateStatus else gateStatus)

negative : String -> String -> String -> String -> String -> IO Bool
negative self candidate oracle gate artifact_stem = do
  (message, outerStatus) <- System.Escaped.run [self,"one",candidate,oracle,gate,artifact_stem]
  save (artifact_stem ++ ".outer.stdout") message
  save (artifact_stem ++ ".outer.status") (show outerStatus ++ "\n")
  Right candidateText <- readFile (artifact_stem ++ ".candidate.status") | _ => pure False
  Right gateText <- readFile (artifact_stem ++ ".gate.status") | _ => pure False
  provenance_only <- if isSuffixOf "/oracle-bypass" candidate then do
    Right expected <- readFile oracle | _ => pure False
    Right actual <- readFile (artifact_stem ++ ".stdout.tsv") | _ => pure False
    let matched = expected==actual && candidateText=="0\n" && gateText=="9\n" && outerStatus==9
    save (artifact_stem ++ ".bypass-value-match.status") (if matched then "0\n" else "1\n")
    pure matched
    else pure True
  let detected = provenance_only && outerStatus/=0 && (candidateText/="0\n" || gateText/="0\n")
  putStrLn ((if detected then "PASS detected " else "FAIL undetected ") ++ candidate)
  pure detected

main : IO ()
main = do
  args <- getArgs
  case args of
    [_,"one",candidate,oracle,gate,artifact_stem] => finish !(one candidate oracle gate artifact_stem)
    [self,"mutants",directory,oracle,gate] => do
      results <- traverse (\name => negative self (directory ++ "/" ++ name) oracle gate (directory ++ "/" ++ name))
        ["wrong-side-sign","omitted-undo","dropped-carry","zero","oracle-bypass"]
      if all id results then pure () else exitWith (ExitFailure 8)
    _ => do putStrLn "usage: Run one CANDIDATE ORACLE GATE PREFIX | Run mutants DIRECTORY ORACLE GATE"
            exitWith (ExitFailure 8)
