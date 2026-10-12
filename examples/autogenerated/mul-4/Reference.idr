module Reference
import Data.Bits
import Data.List
import Data.String
import System
%default covering

public export
record Bounds where
  constructor Interval
  lower, upper : Integer

export
floorQuotient : Integer -> Integer -> Integer
floorQuotient numerator denominator =
  if numerator>=0 then numerator `div` denominator
  else - ((-numerator+denominator-1) `div` denominator)

export
ceilQuotient : Integer -> Integer -> Integer
ceilQuotient numerator denominator = -floorQuotient (-numerator) denominator

export
add : Bounds -> Bounds -> Bounds
add first second = Interval (first.lower+second.lower) (first.upper+second.upper)

export
subtract : Bounds -> Bounds -> Bounds
subtract first second = Interval (first.lower-second.upper) (first.upper-second.lower)

export
scaled : Bounds -> Integer -> Integer -> Bounds
scaled value numerator denominator =
  Interval (floorQuotient (value.lower*numerator) denominator)
           (ceilQuotient (value.upper*numerator) denominator)

export
productBounds : Integer -> Bounds -> Bounds -> Bounds
productBounds base first second =
  let products = [first.lower*second.lower,first.lower*second.upper,first.upper*second.lower,first.upper*second.upper]
      least = foldl min (first.lower*second.lower) products
      greatest = foldl max (first.lower*second.lower) products in
  Interval (floorQuotient least base) (ceilQuotient greatest base)

export
piBounds : Integer -> Nat -> Bounds
piBounds base terms = finish terms 0 (Interval (base `div` 2) (base `div` 2)) (Interval 0 0) where
  -- Euler's positive arctangent series at one; the remaining ratios are <1/2.
  finish : Nat -> Integer -> Bounds -> Bounds -> Bounds
  finish Z index term sum = Interval (4*sum.lower) (4*sum.upper+8*term.upper)
  finish (S rest) index term sum = finish rest (index+1) (scaled term (index+1) (2*index+3)) (add sum term)

export
logTwoBounds : Integer -> Nat -> Bounds
logTwoBounds base terms = finish terms 1 (Interval (base `div` 2) (base `div` 2)) (Interval 0 0) where
  -- log 2=sum 1/(n 2^n), independent of the candidate's atanh series.
  finish : Nat -> Integer -> Bounds -> Bounds -> Bounds
  finish Z index term sum = Interval sum.lower (sum.upper+2*term.upper)
  finish (S rest) index term sum = finish rest (index+1) (scaled term index (2*(index+1))) (add sum term)

export
negativeExponential : Integer -> Nat -> Bounds -> Bounds
negativeExponential base terms argument = reduce 0 argument where
  sumPositive : Nat -> Integer -> Bounds -> Bounds -> Bounds -> Bounds
  sumPositive Z index argument term sum = Interval sum.lower (sum.upper+2*term.upper)
  sumPositive (S rest) index argument term sum =
    sumPositive rest (index+1) argument (scaled (productBounds base term argument) 1 (index+1)) (add sum term)
  squareRepeatedly : Nat -> Bounds -> Bounds
  squareRepeatedly Z value = value
  squareRepeatedly (S rest) value = squareRepeatedly rest (productBounds base value value)
  reduce : Nat -> Bounds -> Bounds
  reduce halvings argument =
    if argument.upper<=base `div` 8 then
      let exponential = sumPositive terms 0 argument (Interval base base) (Interval 0 0)
          reciprocal = Interval (floorQuotient (base*base) exponential.upper) (ceilQuotient (base*base) exponential.lower) in
      squareRepeatedly halvings reciprocal
    else reduce (S halvings) (scaled argument 1 2)

export
rootBounds : Integer -> Nat -> Bounds -> Integer -> Integer -> (Bounds,Bounds)
rootBounds base terms pi numerator denominator =
  let argument = scaled pi numerator (8*denominator)
      square = productBounds base argument argument
      (cosine,sine) = sumTrig terms 0 square (Interval base base) argument (Interval 0 0) (Interval 0 0) in
  double 4 cosine sine where
  sumTrig : Nat -> Integer -> Bounds -> Bounds -> Bounds -> Bounds -> Bounds -> (Bounds,Bounds)
  sumTrig Z index square cosTerm sinTerm cosine sine =
    if index `mod` 2==0 then (Interval cosine.lower (cosine.upper+cosTerm.upper),Interval sine.lower (sine.upper+sinTerm.upper))
    else (Interval (cosine.lower-cosTerm.upper) cosine.upper,Interval (sine.lower-sinTerm.upper) sine.upper)
  sumTrig (S rest) index square cosTerm sinTerm cosine sine =
    sumTrig rest (index+1) square
      (scaled (productBounds base cosTerm square) 1 ((2*index+1)*(2*index+2)))
      (scaled (productBounds base sinTerm square) 1 ((2*index+2)*(2*index+3)))
      (if index `mod` 2==0 then add cosine cosTerm else subtract cosine cosTerm)
      (if index `mod` 2==0 then add sine sinTerm else subtract sine sinTerm)
  double : Nat -> Bounds -> Bounds -> (Bounds,Bounds)
  double Z cosine sine = (cosine,sine)
  double (S rest) cosine sine =
    double rest (subtract (productBounds base cosine cosine) (productBounds base sine sine))
      (scaled (productBounds base cosine sine) 2 1)

export
showBounds : Bounds -> String
showBounds value = show value.lower ++ "\t" ++ show value.upper

main : IO ()
main = traverse_ (\precision => do
  let referencePrecision = precision+128
  let base = shiftL 1 (cast referencePrecision)
  let terms = cast (referencePrecision+32)
  let pi = piBounds base terms
  let logTwo = logTwoBounds base terms
  traverse_ (\constant => putStrLn ("constant\t" ++ show precision ++ "\t" ++ show constant ++ "\t" ++
    show referencePrecision ++ "\t" ++ showBounds (if constant<2 then pi else logTwo))) (the (List Integer) [0..3])
  traverse_ (\(index,(numerator,denominator,power)) => do
    let argument = scaled pi numerator denominator
    let positive = index>=8
    let actualArgument = if positive then subtract (scaled logTwo power 1) argument else argument
    let result = negativeExponential base terms actualArgument
    putStrLn ("exponential\t" ++ show precision ++ "\t" ++ show numerator ++ "\t" ++ show denominator ++ "\t" ++
      (if positive then "1" else "0") ++ "\t" ++ show power ++ "\t" ++ show referencePrecision ++ "\t" ++ showBounds result))
    (zip (the (List Integer) [0..10]) (the (List (Integer,Integer,Integer))
      [(0,1,0),(1,1,0),(1,3,0),(7,13,0),(3,2,0),(200,1,0),(101,1,0),(4294967295,1000000,0),(4,1,30),(9,4,70),(0,1,0)]))
  traverse_ (\denominator => traverse_ (\numerator => do
    let (real,imaginary) = rootBounds base terms pi numerator denominator
    putStrLn ("root\t" ++ show precision ++ "\t" ++ show numerator ++ "\t" ++ show denominator ++ "\t" ++
      show referencePrecision ++ "\t" ++ showBounds real ++ "\t" ++ showBounds imaginary))
    [0,1,denominator `div` 2,denominator-1]) (the (List Integer) [2,3,4,5,7,17,65537,4294967295]))
    (the (List Integer) [101,128,256])
