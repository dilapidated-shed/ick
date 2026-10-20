module PhaseOracle
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
%default covering

weight : Integer -> Integer
weight value = if value==0 then 0 else (value .&. 1)+weight (shiftR value 1)

input : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> (Integer,Integer)
input precision slots rows test row coordinate =
  let base = shiftL 1 (cast precision)
      real = if test<slots then (if coordinate==test then base else 0)
             else (((row*17+coordinate*7+test) `mod` 3)-1)*(if test==slots then base `div` 2 else 1)
      imaginary = if test<slots then 0
                  else (((row*13+coordinate*11+test*3) `mod` 3)-1)*(if test==slots then base `div` 2 else 1) in
  if row>0 && row<64 then (0,0)
  else if rows==944 then ((row-400)*(base `div` 1024),((row*7+coordinate*11) `mod` 631-315)*(base `div` 1024))
  else (real,imaginary)

truncateZero : Integer -> Integer -> Integer
truncateZero numerator denominator = if numerator<0 then -((-numerator) `div` denominator) else numerator `div` denominator

at : Nat -> List item -> Maybe item
at _ [] = Nothing
at Z (first :: rest) = Just first
at (S index) (first :: rest) = at index rest

hexDigit : Integer -> String
hexDigit value = pack [fromMaybe 'x' (at (cast value) (unpack "0123456789abcdef"))]

hexWord : Nat -> Integer -> String
hexWord Z value = ""
hexWord (S count) value = hexWord count (value `div` 16) ++ hexDigit (value `mod` 16)

encoded : Integer -> Integer -> String
encoded precision value =
  let width = (precision+9) `div` 8
      modulus = shiftL 1 (cast (8*width))
      residue = ((value `mod` modulus)+modulus) `mod` modulus in
  hexWord (cast (2*width)) residue

profile : Integer -> Integer -> Integer -> Integer -> IO ()
profile precision axes rows test = do
  let slots = the Integer (shiftL 1 (cast axes))
  traverse_ (\(row,destination) => do
    let products = the (List (Integer,(Integer,Integer))) [(sign, input precision slots rows test row source)
                    | source <- the (List Integer) [0..slots-1],
                      sign <- [(if weight (source .&. destination) `mod` 2==1 then -1 else 1)]]
    let real = truncateZero (sum [sign*real | (sign,(real,imaginary)) <- products]) slots
    let imaginary = truncateZero (sum [sign*imaginary | (sign,(real,imaginary)) <- products]) slots
    putStrLn ("phase\t" ++ show precision ++ "\t" ++ show axes ++ "\t" ++ show rows ++ "\t" ++ show test ++ "\t" ++
      show row ++ "\t" ++ show destination ++ "\t" ++ encoded precision real ++ "\t" ++ encoded precision imaginary))
    [(row,destination) | row <- [0..rows-1],destination <- [0..slots-1]]

main : IO ()
main = do
  traverse_ (\(axes,test) => profile 9 axes 1 test)
    [(axes,test) | axes <- the (List Integer) [1..4],test <- [0..shiftL 1 (cast axes)+1]]
  profile 5 2 129 4
  profile 33 2 129 5
  profile 33 2 944 6
