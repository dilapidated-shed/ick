module LayoutOracle
import Data.Bits
import Data.List
import System
%default covering

power_two : Integer -> Integer
power_two exponent = if exponent<=0 then 1 else 2*power_two (exponent-1)

main : IO ()
main = do
  let boundaries = the (List Integer) [0,1,2,19,20,21,22,31,32,41,42,43,62,63,64,65,126,127,128,129]
  traverse_ (\(guard_width,count,position,control_index,y_index,z_index) =>
    let first = if position==0 then 0 else guard_width-1
        maximum = power_two (guard_width*count)-1
        control = sum [power_two (first+bit*guard_width) | bit <- [0..count-1], ((control_index `div` power_two bit) `mod` 2)==1]
        y = if y_index<20 then (fromMaybe 0 (getAt (cast y_index) boundaries)) .&. maximum else maximum-(21-y_index)
        z = if z_index<20 then (fromMaybe 0 (getAt (cast z_index) boundaries)) .&. maximum else maximum-(21-z_index)
        result = xor y control in
    putStrLn ("packed\t" ++ show guard_width ++ "\t" ++ show count ++ "\t" ++ show first ++ "\t" ++ show control ++ "\t" ++ show y ++ "\t" ++ show z ++ "\t" ++ show result ++ "\t" ++ show z))
    (the (List (Integer,Integer,Integer,Integer,Integer,Integer))
      [(guard_width,count,position,control_index,y_index,z_index) | guard_width <- [6,7], count <- [1..4], position <- [0..1],
        control_index <- [0..15], y_index <- [0..21], z_index <- [0..21]])
