module ResamplingGate
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
import System.File
import ScalarGate
%default covering

lineValid : List String -> List String -> Bool
lineValid expected actual = fromMaybe False $ case (expected,actual) of
  (["line",kind,p,s,t,alpha,example,index,q,rlo,rhi,ilo,ihi],
   ["line",actualKind,actualP,actualS,actualT,actualAlpha,actualExample,actualIndex,real,imaginary]) => do
    precision <- parseInteger p
    bits <- parseInteger q
    realLower <- parseInteger rlo
    realUpper <- parseInteger rhi
    imaginaryLower <- parseInteger ilo
    imaginaryUpper <- parseInteger ihi
    realValue <- hexadecimal precision real
    imaginaryValue <- hexadecimal precision imaginary
    let base = shiftL 1 (cast precision)
    let scale = shiftL 1 (cast (bits-precision))
    let realError = distance (realValue*scale) realLower realUpper
    let imaginaryError = distance (imaginaryValue*scale) imaginaryLower imaginaryUpper
    let bound = precision*precision*scale
    pure ([kind,p,s,t,alpha,example,index]==[actualKind,actualP,actualS,actualT,actualAlpha,actualExample,actualIndex] &&
      bits==precision+128 && realLower<=realUpper && imaginaryLower<=imaginaryUpper &&
      realValue*realValue+imaginaryValue*imaginaryValue<=base*base &&
      realError*realError+imaginaryError*imaginaryError<bound*bound)
  _ => Nothing

validate : List (List String) -> List String -> List String -> Bool
validate reference expected actual = case expected of
  "line" :: _ => lineValid expected actual
  "line-parameter" :: _ => expected==actual
  "nearest" :: _ => expected==actual
  _ => rowValid reference expected actual

main : IO ()
main = do
  [_,referencePath,actualPath,symbolsPath] <- getArgs | _ => exitWith (ExitFailure 9)
  Right reference <- readFile referencePath | _ => exitWith (ExitFailure 9)
  Right actual <- readFile actualPath | _ => exitWith (ExitFailure 9)
  Right symbols <- readFile symbolsPath | _ => exitWith (ExitFailure 9)
  let referenceRows = map words (lines reference)
  let actualRows = map words (lines actual)
  if length referenceRows==3928 && length actualRows==3928 && candidateProvenance symbols &&
     all (\(expected,value) => validate referenceRows expected value) (zip referenceRows actualRows) &&
     all (constantsNarrow actualRows) (the (List Integer) [101,128,256])
    then putStrLn "PASS certified scalars and ordered Gaussian line maps"
    else do putStrLn "FAIL scalar, line value, parameter, certificate or provenance"
            exitWith (ExitFailure 9)
