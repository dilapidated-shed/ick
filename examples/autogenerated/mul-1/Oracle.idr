module Oracle
import Data.List
import Data.Maybe
%default covering

ordinary : Integer -> Integer -> Integer -> Integer
ordinary test field channel = (test*19+field*7+channel*11) `mod` 23 - 11

-- All values below are already scaled by 16. The STAR cases are the original
-- Model.idr seeds/basis and scratch values at the immutable investigation pin.
initial : Integer -> Integer -> Integer -> Integer
initial test field channel =
  if test >= 35 then
    let index = test-35
        seed = if index<12 then index else 17 in
    if channel /= 0 then 0
    else if field<20 then
      if index>=12 then (if field==index-12 then 16 else 0)
      else 4*ordinary seed field 0
    else if field<40 then 4*ordinary seed (field-20) 0
    else if field<240 then 4*ordinary (seed+3) (field-40+1) 0
    else if field<246 then 4*ordinary (seed+5) (field-240) 0
    else 8*(seed+7)
  else
    let value = ordinary test field channel in
    4 * if field<20 then
      if test>=12 && test<32 then (if field==test-12 then (if channel==0 then 1 else -1) else 0)
      else if test==32 then 0
      else if test>=33 then (if test==33 then 1 else -1)*(1099511627776+4294967295+value)
      else value
    else value

expected : Integer -> Integer -> Integer -> Integer -> Integer
expected route test field channel =
  if field>=40 then initial test field channel
  else if route==2 then
    if field<20 then -(initial test (field+20) channel)
    else initial test (field-20) channel
  else if field<20 then initial test field channel
  else initial test field channel + (if route==0 then 1 else -1)*initial test (field-20) channel

hexDigit : Integer -> String
hexDigit value = pack [fromMaybe '0' (getAt (cast value) (unpack "0123456789abcdef"))]

hexWord : Nat -> Integer -> String
hexWord Z value = ""
hexWord (S digits) value = hexWord digits (value `div` 16) ++ hexDigit (value `mod` 16)

recordLine : Integer -> Integer -> Integer -> Integer -> String
recordLine route test field channel =
  let value = expected route test field channel
      unsigned = if value<0 then value+18446744073709551616 else value in
  show route ++ "\t" ++ show test ++ "\t" ++ show field ++ "\t" ++ show channel ++ "\t" ++ hexWord 16 unsigned

-- Export of the original STAR Model's internal scalar vectors. These direct
-- incidence sums retain its seed, basis, side ordering and eight rows. No C
-- state or C result is read by this generator.
triples : List (List Integer)
triples = [[a,b,c] | a <- [0..5], b <- [0..5], c <- [0..5], a<b, b<c]

overlap : List Integer -> List Integer -> Integer
overlap target source = cast (length (filter (`elem` source) target))

neighbors : List (List Integer,List Integer)
neighbors = [(target,source) | target <- triples, source <- triples,
              target/=source, overlap target source==0 || overlap target source==2]

sideInjection : List Integer -> List Integer
sideInjection side =
  [sum [(1-overlap target source)*value `div` 2
        | ((destination,source),value) <- zip neighbors side, destination==target]
    | target <- triples]

scatter : List Integer -> Integer -> List Integer
scatter central star =
  [(sum [value | (index,value) <- zip [0..5] central, elem index target]-star) `div` 2
    | target <- triples]

modelRow : Nat -> List Integer -> List Integer
modelRow step state =
  let source = take 20 state
      target = take 20 (drop 20 state)
      side = take 200 (drop 40 state)
      central = take 6 (drop 240 state)
      star = fromMaybe 0 (getAt 246 state)
      copied = [sum [value | (triple,value) <- zip triples source, triple==control]
                 | (_,control) <- neighbors]
      gathered = [sum [value | (triple,value) <- zip triples source, elem index triple]
                    | index <- [0..5]]
      fields = case step of
        0 => (zipWith (-) target (sideInjection side),side,central,star)
        1 => (zipWith (-) target (scatter central star),side,central,star)
        2 => (target,zipWith (+) side copied,central,star)
        3 => (target,side,zipWith (+) central gathered,star+sum source)
        4 => (zipWith (+) target (scatter central star),side,central,star)
        5 => (zipWith (+) target (sideInjection side),side,central,star)
        6 => (target,side,zipWith (-) central gathered,star-sum source)
        _ => (target,zipWith (-) side copied,central,star)
      (updatedTarget,updatedSide,updatedCentral,updatedStar) = fields in
  source ++ updatedTarget ++ updatedSide ++ updatedCentral ++ [updatedStar]

stageLine : Nat -> Integer -> Nat -> Integer -> Integer -> String
stageLine step test field channel real =
  let value = if channel==0 then real else 0
      unsigned = if value<0 then value+18446744073709551616 else value in
  "stage\t" ++ show step ++ "\t" ++ show test ++ "\t" ++ show field ++ "\t" ++ show channel ++ "\t" ++ hexWord 16 unsigned

emitModel : Nat -> Nat -> Integer -> List Integer -> IO ()
emitModel Z step test state = pure ()
emitModel (S remaining) step test state = do
  let updated = modelRow step state
  traverse_ putStrLn [stageLine step test field channel value
                      | (field,value) <- zip [0..246] updated, channel <- [0..1]]
  emitModel remaining (S step) test updated

main : IO ()
main = do
  traverse_ putStrLn [recordLine route test field channel | route <- [0..2], test <- [0..66],
                      field <- [0..246], channel <- [0..1]]
  traverse_ (\test => emitModel 8 0 test (map (\field => initial test field 0) [0..246])) [35..66]
