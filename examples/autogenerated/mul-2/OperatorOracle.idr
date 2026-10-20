module OperatorOracle
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
%default covering

triples : List Integer
triples = [7,11,13,14]

at : Nat -> List item -> Maybe item
at _ [] = Nothing
at Z (first :: rest) = Just first
at (S position) (first :: rest) = at position rest

selected : Integer -> Integer -> Bool
selected triple position = (shiftR triple (cast position) .&. 1)==1

indicator : Integer -> Integer
indicator role =
  let coordinates = [role `div` 16,(role `div` 4) `mod` 4,role `mod` 4]
      masks = map (\coordinate => fromMaybe 0 (at (cast coordinate) triples)) coordinates in
  sum [shiftL 1 (cast address) | address <- the (List Integer) [0..63],
       all id (zipWith selected masks [address `div` 16,(address `div` 4) `mod` 4,address `mod` 4])]

weight : Integer -> Integer
weight value = sum [(shiftR value (cast bit) .&. 1) | bit <- the (List Integer) [0..63]]

hexDigit : Integer -> String
hexDigit digit = pack [fromMaybe 'x' (at (cast digit) (unpack "0123456789abcdef"))]

encoded : Integer -> String
encoded value =
  let residue = (value*1024) `mod` 4294967296 in
  concat [hexDigit ((shiftR residue (cast shift)) .&. 15) | shift <- the (List Integer) [28,24,20,16,12,8,4,0]]

output : Integer -> Integer -> Integer -> Integer -> String
output frequency group basis destination =
  let source = if destination<64 then destination+64 else if destination<128 then destination-64 else destination
      real = if group==0 then (if source==basis then 1 else 0) else (source*17+group*11) `mod` 41-20
      imaginary = if group==0 then 0 else (source*13+group*7) `mod` 37-18
      sign = if source>=64 && source<128 then -1 else 1
      lineParity = weight (indicator source .&. frequency) `mod` 2
      phase = (weight frequency+(if source<64 then 2*lineParity else 0)) `mod` 4
      (nextReal,nextImaginary) = if phase==0 then (real,imaginary) else if phase==1 then (-imaginary,real)
                               else if phase==2 then (-real,-imaginary) else (imaginary,-real) in
  encoded (sign*nextReal) ++ encoded (sign*nextImaginary)

main : IO ()
main = do
  let frequencies = the (List Integer) [123456789,0,1,123456789,18446744073709551615,9223372036854775808]
  traverse_ (\(group,frequency) =>
    traverse_ (\basis => putStrLn ("phase-operator\t" ++ show frequency ++ "\t" ++ show group ++ "\t" ++ show basis ++ "\t" ++
      concat [output frequency group basis destination | destination <- the (List Integer) [0..943]]))
      (if group==0 then [0..943] else [0])) (zip (the (List Integer) [0..5]) frequencies)
