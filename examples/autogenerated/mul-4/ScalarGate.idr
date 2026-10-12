module ScalarGate
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
import System.File
import Reference
%default covering

number : String -> Maybe Integer
number = parseInteger

export
hexadecimal : Integer -> String -> Maybe Integer
hexadecimal precision text = do
  let digits = unpack text
  if cast (length digits)/=2*((precision+9) `div` 8) then Nothing else do
    values <- traverse (\digit => lookup digit (zip (unpack "0123456789abcdef") (the (List Integer) [0..15]))) digits
    first :: rest <- pure values | _ => Nothing
    let magnitude = foldl (\previous,digit => 16*previous+digit) 0 values
    pure (if first>=8 then magnitude-shiftL 1 (cast (4*length digits)) else magnitude)

referenceConstant : List (List String) -> Integer -> Integer -> Maybe (Integer,Bounds)
referenceConstant rows precision constant =
  case filter (\row => take 3 row==["constant",show precision,show constant]) rows of
    [[_,_,_,q,low,high]] => do
      bits <- number q
      lower <- number low
      upper <- number high
      pure (bits,Interval lower upper)
    _ => Nothing

candidateConstant : List (List String) -> Integer -> Integer -> Maybe Integer
candidateConstant rows precision constant =
  case filter (\row => take 3 row==["constant",show precision,show constant]) rows of
    [[_,_,_,value]] => hexadecimal (precision+64) value
    _ => Nothing

export
constantsNarrow : List (List String) -> Integer -> Bool
constantsNarrow rows precision = fromMaybe False $ do
  piLower <- candidateConstant rows precision 0
  piUpper <- candidateConstant rows precision 1
  logLower <- candidateConstant rows precision 2
  logUpper <- candidateConstant rows precision 3
  let base = shiftL 1 (cast (precision+64))
  let maximumWidth = shiftL 1 32
  pure (piLower>3*base && piUpper<4*base && piLower<=piUpper && piUpper-piLower<maximumWidth &&
        logLower>base `div` 2 && logUpper<base && logLower<=logUpper && logUpper-logLower<maximumWidth)

rangeValid : List (List String) -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Bool
rangeValid rows precision numerator denominator positive power shifts = fromMaybe False $ do
  (q,pi) <- referenceConstant rows precision 0
  (qLog,logTwo) <- referenceConstant rows precision 2
  if q/=qLog || shifts<0 || shifts>8*precision || denominator<=0 then Nothing else do
    let original = scaled pi numerator denominator
    let argument = if positive==1 then subtract (scaled logTwo power 1) original else original
    let remainder = subtract argument (scaled logTwo shifts 1)
    pure (remainder.lower>=0 && remainder.upper<=2*logTwo.upper)

export
distance : Integer -> Integer -> Integer -> Integer
distance value lower upper = max (abs (value-lower)) (abs (value-upper))

export
rowValid : List (List String) -> List String -> List String -> Bool
rowValid referenceRows expected actual = fromMaybe False $ case (expected,actual) of
  (["constant",p,index,q,lo,hi],["constant",actualP,actualIndex,hex]) => do
    precision <- number p
    bits <- number q
    constant <- number index
    lower <- number lo
    upper <- number hi
    value <- hexadecimal (precision+64) hex
    let aligned = shiftL value (cast (bits-precision-64))
    pure (p==actualP && index==actualIndex && bits==precision+128 && lower<=upper &&
      (if constant `mod` 2==0 then aligned<=lower else aligned>=upper))
  (["exponential",p,j,k,positive,power,q,lo,hi],
   ["exponential",actualP,actualJ,actualK,actualPositive,actualPower,hex,terms,shifts,zero]) => do
    precision <- number p
    numerator <- number j
    denominator <- number k
    sign <- number positive
    exponent <- number power
    bits <- number q
    lower <- number lo
    upper <- number hi
    count <- number terms
    rangeShifts <- number shifts
    early <- number zero
    value <- hexadecimal precision hex
    let scale = shiftL 1 (cast (bits-precision))
    let earlyZero = sign==0 && numerator>denominator*precision
    pure ([p,j,k,positive,power]==[actualP,actualJ,actualK,actualPositive,actualPower] &&
      bits==precision+128 && lower<=upper && value>=0 && value<=shiftL 1 (cast precision) &&
      distance (value*scale) lower upper<2*scale &&
      count==(if earlyZero then 0 else precision+80) && early==(if earlyZero then 1 else 0) &&
      (if earlyZero then rangeShifts==0 else rangeValid referenceRows precision numerator denominator sign exponent rangeShifts))
  (["root",p,j,k,q,rlo,rhi,ilo,ihi],["root",actualP,actualJ,actualK,real,imaginary,terms,shifts]) => do
    precision <- number p
    bits <- number q
    realLower <- number rlo
    realUpper <- number rhi
    imaginaryLower <- number ilo
    imaginaryUpper <- number ihi
    realValue <- hexadecimal precision real
    imaginaryValue <- hexadecimal precision imaginary
    count <- number terms
    rangeShifts <- number shifts
    let base = shiftL 1 (cast precision)
    let scale = shiftL 1 (cast (bits-precision))
    let realError = distance (realValue*scale) realLower realUpper
    let imaginaryError = distance (imaginaryValue*scale) imaginaryLower imaginaryUpper
    pure ([p,j,k]==[actualP,actualJ,actualK] && bits==precision+128 && realLower<=realUpper && imaginaryLower<=imaginaryUpper &&
      realValue*realValue+imaginaryValue*imaginaryValue<=base*base &&
      realError*realError+imaginaryError*imaginaryError<4*scale*scale &&
      count==2*((precision+71) `div` 2+1)+precision+80 && rangeShifts==0)
  _ => Nothing

allowed : List String
allowed = ["calloc","free","memcmp","memcpy","memmove","memset","printf","sprintf","strcmp","putchar","putc","clock","getrusage",
           "fprintf","fputs","fwrite","ferror","stderr","stdout","__libc_start_main",
           "__cxa_finalize","__gmon_start__","_ITM_deregisterTMCloneTable","_ITM_registerTMCloneTable"]

symbol : String -> String
symbol line = pack (takeWhile (/= '@') (unpack (fromMaybe "" (last' (words line)))))

export
candidateProvenance : String -> Bool
candidateProvenance symbols =
  let names = map symbol (filter (/= "") (lines symbols)) in
  not (null names) && elem "calloc" names && elem "__libc_start_main" names && all (`elem` allowed) names

main : IO ()
main = do
  [_,referencePath,actualPath,symbolsPath] <- getArgs | _ => exitWith (ExitFailure 9)
  Right reference <- readFile referencePath | _ => exitWith (ExitFailure 9)
  Right actual <- readFile actualPath | _ => exitWith (ExitFailure 9)
  Right symbols <- readFile symbolsPath | _ => exitWith (ExitFailure 9)
  let referenceRows = map words (lines reference)
  let actualRows = map words (lines actual)
  let provenance = candidateProvenance symbols
  if length referenceRows==141 && length actualRows==141 && provenance &&
     all (\(expected,value) => rowValid referenceRows expected value) (zip referenceRows actualRows) &&
     all (constantsNarrow actualRows) (the (List Integer) [101,128,256])
    then putStrLn "PASS independently bounded scalar values, certificates and provenance"
    else do putStrLn "FAIL scalar value, interval, certificate or provenance"
            exitWith (ExitFailure 9)
