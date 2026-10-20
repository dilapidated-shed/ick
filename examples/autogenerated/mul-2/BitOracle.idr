module BitOracle
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
%default covering

at : Nat -> List item -> Maybe item
at _ [] = Nothing
at Z (first :: rest) = Just first
at (S position) (first :: rest) = at position rest

mask : Integer -> Integer
mask coordinate = fromMaybe 0 (at (cast coordinate) [7,11,13,14])

entry : Integer -> Integer -> Integer
entry source coordinate =
  product [(if (shiftR (mask triple) (cast position) .&. 1)==0 then 0
           else if (mask triple .&. 1)==1 then 2 else -1)
           | (triple,position) <- zip [source `div` 16,(source `div` 4) `mod` 4,source `mod` 4]
                                     [coordinate `div` 16,(coordinate `div` 4) `mod` 4,coordinate `mod` 4]]

address : Integer -> Integer -> Integer
address role coordinate =
  let source = if role<64 then role+64 else if role<128 then role-64 else role
      base = if coordinate==0 then 222 else (17*coordinate+11) `mod` 223
      correction = if source<64 then -191*entry source coordinate else 0 in
  (base+correction+(if coordinate==0 then 1 else 0)) `mod` 223

hexDigit : Integer -> String
hexDigit digit = pack [fromMaybe 'x' (at (cast digit) (unpack "0123456789abcdef"))]

encoded : Integer -> String
encoded value = concat [hexDigit ((shiftR value (cast shift)) .&. 15) | shift <- the (List Integer) [60,56,52,48,44,40,36,32,28,24,20,16,12,8,4,0]]

output : Integer -> Integer -> String
output group destination =
  let source = if destination<64 then destination+64 else if destination<128 then destination-64 else destination
      value = if group==5 then (source*19+17) `mod` 257
              else if source `div` 64==group then shiftL 1 (cast (source `mod` 64)) else 0 in
  encoded value

main : IO ()
main = traverse_ (\group => do
  putStrLn ("bit-operator\t" ++ show group ++ "\t" ++ concat [output group destination | destination <- the (List Integer) [0..319]])
  if group==0 then traverse_ (\role => putStrLn ("bit-address\t" ++ show role ++ "\t" ++
    concat (intersperse "," [show (address role coordinate) | coordinate <- the (List Integer) [0..63]]))) (the (List Integer) [0..319])
    else pure ()) (the (List Integer) [0..5])
