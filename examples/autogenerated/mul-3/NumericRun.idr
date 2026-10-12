module NumericRun
import Data.List
import Data.So
import Data.String
import System
import System.Clock
import System.File
%default covering

save : String -> String -> IO ()
save path contents = do
  Right () <- writeFile path contents | _ => exitWith (ExitFailure 8)
  pure ()
finish : Int -> IO ()
finish 0 = pure ()
finish status =
  let retained=if status>0 && status<256 then status else 8 in
  case choose (retained/=0) of
    Left nonzero => exitWith (ExitFailure retained @{nonzero})
    Right _ => exitWith (ExitFailure 8)
one : String -> String -> String -> String -> String -> IO Int
one kind candidate reference gate stem = do
  _ <- setEnv "MUL3_ORACLE_PATH" reference True
  (symbols,symbolStatus) <- System.Escaped.run ["nm","-D","--undefined-only",candidate]
  save (stem ++ ".symbols") symbols
  save (stem ++ ".symbols.status") (show symbolStatus ++ "\n")
  if symbolStatus/=0 then pure symbolStatus else do
    started <- clockTime Monotonic
    (actual,candidateStatus) <- System.run (escapeCmd [candidate,kind] ++ " 2> " ++ escapeArg (stem ++ ".stderr"))
    finished <- clockTime Monotonic
    save (stem ++ ".wall-ns") (show (toNano (timeDifference finished started)) ++ "\n")
    save (stem ++ ".stdout.tsv") actual
    save (stem ++ ".candidate.status") (show candidateStatus ++ "\n")
    (message,gateStatus) <- System.Escaped.run [gate,kind,reference,stem ++ ".stdout.tsv",stem ++ ".symbols",stem ++ ".stderr"]
    save (stem ++ ".gate.stdout") message
    save (stem ++ ".gate.status") (show gateStatus ++ "\n")
    putStr message
    pure (if candidateStatus/=0 then candidateStatus else gateStatus)
negative : String -> String -> String -> String -> String -> String -> IO Bool
negative self kind candidate reference gate stem = do
  (message,outerStatus) <- System.Escaped.run [self,"one",kind,candidate,reference,gate,stem]
  save (stem ++ ".outer.stdout") message
  save (stem ++ ".outer.status") (show outerStatus ++ "\n")
  Right candidateText <- readFile (stem ++ ".candidate.status") | _ => pure False
  Right gateText <- readFile (stem ++ ".gate.status") | _ => pure False
  special <- if isSuffixOf "/oracle-bypass" candidate then do
    Right expected <- readFile reference | _ => pure False
    Right actual <- readFile (stem ++ ".stdout.tsv") | _ => pure False
    let matched=expected==actual && candidateText=="0\n" && gateText=="9\n" && outerStatus==9
    save (stem ++ ".bypass-value-match.status") (if matched then "0\n" else "1\n")
    pure matched
    else if isSuffixOf "/forced-exit" candidate
      then pure (candidateText=="57\n" && gateText=="0\n" && outerStatus==57)
      else pure True
  let detected=special && outerStatus/=0 && (candidateText/="0\n" || gateText/="0\n")
  putStrLn ((if detected then "PASS detected " else "FAIL undetected ") ++ candidate)
  pure detected
main : IO ()
main = do
  args <- getArgs
  case args of
    [_,"one",kind,candidate,reference,gate,stem] => finish !(one kind candidate reference gate stem)
    [self,"mutants",directory,gate] => do
      results <- traverse (\(name,kind) => negative self kind (directory ++ "/" ++ name)
        (directory ++ "/" ++ kind ++ "-v1.tsv") gate (directory ++ "/" ++ name))
        [("inverse-phase","child"),("wrap","child"),("lb-order","transform"),("one-product","packed"),
         ("r-m-scale","convolution"),("round-location","phase"),("zero","child"),("oracle-bypass","child"),("forced-exit","child")]
      if all id results then pure () else exitWith (ExitFailure 8)
    _ => exitWith (ExitFailure 8)
