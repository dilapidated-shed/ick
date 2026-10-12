module ParameterOracle
import Data.Bits
import Data.List
import Data.Maybe
import System
%default covering

hexDigit : Integer -> String
hexDigit value = pack [fromMaybe 'x' (lookup value (zip (the (List Integer) [0..15]) (unpack "0123456789abcdef")))]
hexWord : Nat -> Integer -> String
hexWord Z value = ""
hexWord (S digits) value = hexWord digits (value `div` 16) ++ hexDigit (value `mod` 16)
main : IO ()
main = do
  let p=the Integer 256
  let b=the Integer 3
  let gamma=the Integer 144
  let sourceError=(4*p*p+1024)*shiftL 1 (cast gamma)
  let recoveryError=shiftL 1 (cast (2*b+4))*15*15*(3*sourceError+2)
  if 2*recoveryError<shiftL 1 (cast p)
    then pure ()
    else exitWith (ExitFailure 10)
  putStrLn "parameters\t256\t3\t8\t2\t8\t3\t5\t4\t8\t1\t3\t1\t2\t15\t32\t144\t4\t3"
  putStrLn ("recovery\t256\t1\t147\t1024\t263168\t144\t" ++ hexWord 64 recoveryError)
  putStrLn "published-refusal\t3"
