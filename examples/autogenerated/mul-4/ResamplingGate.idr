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

tensorValid : List String -> List String -> Bool
tensorValid expected actual = fromMaybe False $ case (expected,actual) of
  (["tensor",kind,p,prefixIndex,row,column,tail,q,rlo,rhi,ilo,ihi],
   ["tensor",actualKind,actualP,actualPrefix,actualRow,actualColumn,actualTail,real,imaginary]) => do
    precision <- parseInteger p
    bits <- parseInteger q
    r <- parseInteger row
    c <- parseInteger column
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
    let bound = (if kind=="A" then 2 else 4)*precision*precision*scale
    let padding = if kind=="A" then r>=17 || c>=16 else r>=12 || c>=11
    pure ([kind,p,prefixIndex,row,column,tail]==[actualKind,actualP,actualPrefix,actualRow,actualColumn,actualTail] &&
      bits==precision+128 && realLower<=realUpper && imaginaryLower<=imaginaryUpper &&
      realValue*realValue+imaginaryValue*imaginaryValue<=base*base &&
      (not padding || (realValue==0 && imaginaryValue==0)) &&
      realError*realError+imaginaryError*imaginaryError<bound*bound)
  _ => Nothing

identityValid : List String -> List String -> Bool
identityValid expected actual = fromMaybe False $ case (expected,actual) of
  (["identity",p,s,t,alpha,index,q,rlo,rhi,ilo,ihi],
   ["identity",actualP,actualS,actualT,actualAlpha,actualIndex,real,imaginary]) => do
    precision <- parseInteger p
    target <- parseInteger t
    dilation <- parseInteger alpha
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
    let bound = shiftL (2*precision*precision+4*target) (cast (2*dilation*dilation))*scale
    pure ([p,s,t,alpha,index]==[actualP,actualS,actualT,actualAlpha,actualIndex] &&
      bits==precision+128 && realLower<=realUpper && imaginaryLower<=imaginaryUpper &&
      realValue*realValue+imaginaryValue*imaginaryValue<4*base*base &&
      realError*realError+imaginaryError*imaginaryError<bound*bound)
  _ => Nothing

validate : List (List String) -> List String -> List String -> Bool
validate reference expected actual = case expected of
  "line" :: _ => lineValid expected actual
  "tensor" :: _ => tensorValid expected actual
  "identity" :: _ => identityValid expected actual
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
  if length referenceRows==8090 && length actualRows==8090 && candidateProvenance symbols &&
     all (\(expected,value) => validate referenceRows expected value) (zip referenceRows actualRows) &&
     all (constantsNarrow actualRows) (the (List Integer) [101,128,256])
    then putStrLn "PASS certified scalars and ordered Gaussian line maps"
    else do putStrLn "FAIL scalar, line value, parameter, certificate or provenance"
            exitWith (ExitFailure 9)
