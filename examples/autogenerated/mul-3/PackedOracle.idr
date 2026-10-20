module PackedOracle
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
%default covering

point : Integer -> Integer -> Integer -> Integer -> Integer -> (Integer,Integer)
point precision length test operand index =
  let base = shiftL 1 (cast precision) in
  if test==0 then (base,0)
  else if test==1 then ((if (index+operand) `mod` 2==1 then -base else base),0)
  else if test==2 then (0,(if operand==1 && index `mod` 2==1 then -base else base))
  else if test==3 then ((if (index+operand) `mod` 2==1 then -base `div` 2 else base `div` 2),
                       (if index `mod` 2==1 then base `div` 2 else -base `div` 2))
  else if test==4 then ((if index==(if operand==1 then 1 else length-1) then base else 0),0)
  else if test==5 then ((if index `mod` 2==1 then -1 else 1),(if operand==1 then 1 else 0))
  else if test==6 then ((if operand==1 then base `div` 4 else base `div` 2),(if operand==1 then base `div` 2 else -base `div` 2))
  else (((index*7+operand*3) `mod` 3-1)*(base `div` 4),((index*11+operand*5) `mod` 5-2)*(base `div` 4))

positiveResidue : Integer -> Integer -> Integer
positiveResidue value modulus = ((value `mod` modulus)+modulus) `mod` modulus

coefficient : Integer -> Integer -> Integer -> Integer -> (Integer,Integer)
coefficient precision length test destination =
  let products = map contribution [0..length-1] in
  (sum (map fst products),sum (map snd products)) where
  contribution : Integer -> (Integer,Integer)
  contribution index =
    let other = positiveResidue (destination-index) length
        sign = if index+other>=length then -1 else 1
        (real,imaginary) = point precision length test 0 index
        (otherReal,otherImaginary) = point precision length test 1 other in
    (sign*(real*otherReal-imaginary*otherImaginary),sign*(real*otherImaginary+imaginary*otherReal))

at : Nat -> List item -> Maybe item
at _ [] = Nothing
at Z (first :: rest) = Just first
at (S position) (first :: rest) = at position rest

hexDigit : Integer -> String
hexDigit value = pack [fromMaybe 'x' (at (cast value) (unpack "0123456789abcdef"))]

hexWord : Nat -> Integer -> String
hexWord Z value = ""
hexWord (S digits) value = hexWord digits (value `div` 16) ++ hexDigit (value `mod` 16)

encoded : Integer -> Integer -> String
encoded bits value =
  let width = (bits+9) `div` 8
      modulus = shiftL 1 (cast (8*width)) in
  hexWord (cast (2*width)) (positiveResidue value modulus)

bitLength : Integer -> Integer
bitLength value = if value==0 then 0 else 1+bitLength (value `div` 2)

basePower : Integer -> Nat -> Integer
basePower base Z = 1
basePower base (S exponent) = base*basePower base exponent

evaluation : Integer -> Integer -> Integer -> Integer -> Bool -> Integer
evaluation precision length test operand imaginary =
  let base = shiftL 1 (cast (4*precision)) in
  sum [(if imaginary then snd value else fst value)*basePower base (cast index)
        | index <- [0..length-1], value <- [point precision length test operand index]]

truncateZero : Integer -> Integer -> Integer
truncateZero numerator denominator = if numerator<0 then -((-numerator) `div` denominator) else numerator `div` denominator

profile : Integer -> Integer -> Integer -> IO ()
profile precision length test = do
  let logarithm = if length==2 then 1 else if length==4 then 2 else 3
  let raw = [coefficient precision length test index | index <- [0..length-1]]
  traverse_ (\(index,(real,imaginary)) => putStrLn ("numerator\t" ++ show precision ++ "\t" ++ show length ++ "\t" ++
    show test ++ "\t" ++ show index ++ "\t" ++ encoded (2*precision+logarithm) real ++ "\t" ++ encoded (2*precision+logarithm) imaginary))
    (zip (the (List Integer) [0..length-1]) raw)
  let pairs = [(evaluation precision length test 0 False,evaluation precision length test 1 False),
               (evaluation precision length test 0 True,evaluation precision length test 1 True),
               (evaluation precision length test 0 False,evaluation precision length test 1 True),
               (evaluation precision length test 0 True,evaluation precision length test 1 False)]
  traverse_ (\(index,(first,second)) => putStrLn ("short\t" ++ show precision ++ "\t" ++ show length ++ "\t" ++ show test ++ "\t" ++
    show index ++ "\t" ++ show (bitLength (abs first)) ++ "\t" ++ show (bitLength (abs second)) ++ "\t" ++ show (bitLength (abs (first*second))) ++ "\treduced-schoolbook"))
    (zip (the (List Integer) [0..3]) pairs)
  let denominator = shiftL length (cast precision)
  traverse_ (\(index,(real,imaginary)) => putStrLn ("packed\t" ++ show precision ++ "\t" ++ show length ++ "\t" ++ show test ++ "\t" ++
    show index ++ "\t" ++ encoded precision (truncateZero real denominator) ++ "\t" ++ encoded precision (truncateZero imaginary denominator)))
    (zip (the (List Integer) [0..length-1]) raw)

main : IO ()
main = traverse_ (\(precision,length,test) => profile precision length test)
  [(precision,length,test) | precision <- the (List Integer) [2,3,5,9,33,101,256],length <- [2,4,8],
    length<shiftL 1 (cast precision),test <- [0..7]]
