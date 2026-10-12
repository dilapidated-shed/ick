module CRTOracle
import Data.List
import Data.Maybe
import System
%default covering

G : Type
G = (Integer,Integer)
at : Integer -> List item -> item -> item
at index values fallback = fromMaybe fallback (lookup index (zip (the (List Integer) [0..cast (length values)-1]) values))
residue : Integer -> Integer -> Integer
residue value modulus = ((value `mod` modulus)+modulus) `mod` modulus
hexDigit : Integer -> String
hexDigit value = pack [at value (unpack "0123456789abcdef") 'x']
hexWord : Nat -> Integer -> String
hexWord Z value = ""
hexWord (S digits) value = hexWord digits (value `div` 16) ++ hexDigit (value `mod` 16)
encoded : Integer -> String
encoded value = hexWord 4 (residue value 65536)
original : Integer -> Integer -> G
original test index =
  if test<15 then ((if index==test then 512 else 0),0)
  else if test<30 then (0,(if index==test-15 then 512 else 0))
  else if test==30 then (index-7,2*index-13)
  else ((9-index)*128,((index*7+2) `mod` 11-5)*128)
padding : Integer -> List G
padding test = map value [(row,column) | row <- the (List Integer) [0..3],column <- [0..7]] where
  value : (Integer,Integer) -> G
  value (row,column) = if row<3 && column<5 then original test (3*column+row) else (0,0)
directPhi : Integer -> List G
directPhi test = map value [(row,column) | row <- the (List Integer) [0..3],column <- [0..7]] where
  value : (Integer,Integer) -> G
  value (row,column) = case find (\ordinary => ordinary `mod` 3==row && (2*ordinary) `mod` 5==column) [0..14] of
    Nothing => (0,0)
    Just index => original test index
emit : Integer -> Integer -> String -> List G -> IO ()
emit test inverse stage values = traverse_ (\(index,(real,imaginary)) => putStrLn
  ("crt\t" ++ show test ++ "\t" ++ show inverse ++ "\t" ++ stage ++ "\t" ++ show index ++ "\t" ++ encoded real ++ "\t" ++ encoded imaginary))
  (zip (the (List Integer) [0..cast (length values)-1]) values)
main : IO ()
main = do
  let coordinates=the (List (Integer,Integer)) [(index `mod` 3,(2*index) `mod` 5) | index <- the (List Integer) [0..14]]
  if length (nub coordinates)==15 then pure () else exitWith (ExitFailure 10)
  traverse_ (\test => do
    emit test 0 "padding" (padding test)
    emit test 0 "crt-axis-1" (directPhi test)
    emit test 0 "crt-axis-0" (directPhi test)
    emit test 0 "forward" (directPhi test)
    emit test 1 "crt-axis-0" (directPhi test)
    emit test 1 "crt-axis-1" (padding test)
    emit test 1 "inverse" [original test index | index <- [0..14]]) (the (List Integer) [0..31])
