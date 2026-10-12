module NumericOracle
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
%default covering

G : Type
G = (Integer,Integer)
A : Type
A = List G
finiteIndices : Integer -> List Integer
finiteIndices count = if count<=0 then [] else [0..count-1]
indices : List item -> List Integer
indices values = finiteIndices (cast (length values))

at : Integer -> List item -> item -> item
at position values fallback = fromMaybe fallback (lookup position (zip (the (List Integer) [0..cast (length values)-1]) values))

power : Integer -> Integer
power exponent = shiftL 1 (cast exponent)

residue : Integer -> Integer -> Integer
residue value modulus = ((value `mod` modulus)+modulus) `mod` modulus

truncateZero : Integer -> Integer -> Integer
truncateZero numerator denominator = if numerator<0 then -((-numerator) `div` denominator) else numerator `div` denominator

add : G -> G -> G
add (real,imaginary) (otherReal,otherImaginary) = (real+otherReal,imaginary+otherImaginary)
scale : Integer -> G -> G
scale factor (real,imaginary) = (factor*real,factor*imaginary)
multiply : G -> G -> G
multiply (real,imaginary) (otherReal,otherImaginary) = (real*otherReal-imaginary*otherImaginary,real*otherImaginary+imaginary*otherReal)
gaussianSum : A -> G
gaussianSum = foldl add (0,0)
divide : Integer -> G -> G
divide denominator (real,imaginary) = (truncateZero real denominator,truncateZero imaginary denominator)

hexDigit : Integer -> String
hexDigit value = pack [at value (unpack "0123456789abcdef") 'x']
hexWord : Nat -> Integer -> String
hexWord Z value = ""
hexWord (S digits) value = hexWord digits (value `div` 16) ++ hexDigit (value `mod` 16)
encoded : Integer -> Integer -> String
encoded precision value =
  let width=(precision+9) `div` 8 in hexWord (cast (2*width)) (residue value (power (8*width)))
emit : String -> Integer -> Integer -> Integer -> Integer -> A -> IO ()
emit tag precision profile test stage values = traverse_ (\(index,(real,imaginary)) =>
  putStrLn (tag ++ "\t" ++ show precision ++ "\t" ++ show profile ++ "\t" ++ show test ++ "\t" ++ show stage ++ "\t" ++ show index ++ "\t" ++ encoded precision real ++ "\t" ++ encoded precision imaginary))
  (zip (the (List Integer) [0..cast (length values)-1]) values)

logarithm : Integer -> Integer
logarithm value = if value<=1 then 0 else 1+logarithm (value `div` 2)
weight : Integer -> Integer
weight value = if value==0 then 0 else (value .&. 1)+weight (shiftR value 1)
bits : Integer -> Integer
bits value = if value==0 then 0 else 1+bits (value `div` 2)

monomial : Integer -> Integer -> A -> A
monomial ring exponent values = map moved [0..ring-1] where
  moved : Integer -> G
  moved destination =
    let reduced=residue exponent (2*ring)
        shift=reduced `mod` ring
        source=residue (destination-shift) ring
        common=if reduced>=ring then -1 else 1
        sign=common*(if source+shift>=ring then -1 else 1) in scale sign (at source values (0,0))

slot : List Integer -> Integer -> Integer -> Integer
slot lengths axis bit =
  sum [1 | level <- finiteIndices bit,other <- lengths,logarithm other>level] +
  sum [1 | earlier <- finiteIndices axis,logarithm (at earlier lengths 1)>bit]
axisOffset : List Integer -> Integer -> Integer
axisOffset lengths axis = sum (map logarithm (take (cast axis) lengths))
location : List Integer -> Integer -> Integer
location lengths logical = sum [((logical `div` power (axisOffset lengths axis+bit)) `mod` 2)*power (slot lengths axis bit)
  | axis <- indices lengths,bit <- finiteIndices (logarithm (at axis lengths 1))]
reversed : List Integer -> Integer -> Integer
reversed lengths logical = sum [((logical `div` power (axisOffset lengths axis+bit)) `mod` 2)*power (axisOffset lengths axis+logarithm (at axis lengths 1)-1-bit)
  | axis <- indices lengths,bit <- finiteIndices (logarithm (at axis lengths 1))]
stored : List Integer -> Integer -> Integer
stored lengths frequency = location lengths (reversed lengths frequency)
records : List Integer -> Integer
records = product
relocate : Integer -> List Integer -> A -> A
relocate ring lengths values = concatMap moved [0..records lengths-1] where
  moved : Integer -> A
  moved physical =
    let logical=fromMaybe 0 (find (\address => location lengths address==physical) [0..records lengths-1]) in
    [at (logical*ring+coefficient) values (0,0) | coefficient <- [0..ring-1]]
restore : Integer -> List Integer -> A -> A
restore ring lengths values = [at (location lengths logical*ring+coefficient) values (0,0)
  | logical <- [0..records lengths-1],coefficient <- [0..ring-1]]
unstore : Integer -> List Integer -> A -> A
unstore ring lengths values = [at (stored lengths frequency*ring+coefficient) values (0,0)
  | frequency <- [0..records lengths-1],coefficient <- [0..ring-1]]

selected : List Integer -> Integer -> List Integer
selected lengths position = [slot lengths axis position | axis <- [0..cast (length lengths)-1],logarithm (at axis lengths 1)>position]
replaceSelected : Integer -> List Integer -> Integer -> Integer
replaceSelected address slots source = foldl replace address (zip (the (List Integer) [0..cast (length slots)-1]) slots) where
  replace : Integer -> (Integer,Integer) -> Integer
  replace address (axis,position) =
    address-((address `div` power position) `mod` 2)*power position+((source `div` power axis) `mod` 2)*power position
selectedValue : Integer -> List Integer -> Integer
selectedValue address slots = sum [((address `div` power position) `mod` 2)*power axis
  | (axis,position) <- zip (the (List Integer) [0..cast (length slots)-1]) slots]
layer : Integer -> List Integer -> Integer -> A -> A
layer ring lengths position values = map value [(address,coefficient) | address <- [0..records lengths-1],coefficient <- [0..ring-1]] where
  value : (Integer,Integer) -> G
  value (address,coefficient) =
    let slots=selected lengths position
        count=power (cast (length slots))
        destination=selectedValue address slots in
    divide count (gaussianSum [scale (if weight (source .&. destination) `mod` 2==1 then -1 else 1)
      (at (replaceSelected address slots source*ring+coefficient) values (0,0)) | source <- [0..count-1]])
twiddle : Integer -> List Integer -> Integer -> Bool -> A -> A
twiddle ring lengths position opposite values = concatMap moved [0..records lengths-1] where
  moved : Integer -> A
  moved address =
    let exponent = -sum [(2*ring `div` power (position+1))*((address `div` power (slot lengths axis position)) `mod` 2)*
          sum [((address `div` power (slot lengths axis bit)) `mod` 2)*power bit | bit <- finiteIndices position]
          | axis <- [0..cast (length lengths)-1],logarithm (at axis lengths 1)>position]
        polynomial=[at (address*ring+coefficient) values (0,0) | coefficient <- [0..ring-1]] in
    monomial ring (if opposite then -exponent else exponent) polynomial

procedure : Integer -> List Integer -> Bool -> A -> (List (Integer,A),A)
procedure ring lengths opposite input =
  let rounds=foldl max 0 (map logarithm lengths)
      positions=if opposite then [0..rounds-1] else reverse [0..rounds-1]
      initial=if opposite then input else relocate ring lengths input
      (stages,result)=run positions initial in
  (stages,if opposite then restore ring lengths result else result) where
  run : List Integer -> A -> (List (Integer,A),A)
  run [] values = ([],values)
  run (position :: rest) values =
    let result=if opposite then layer ring lengths position (twiddle ring lengths position True values)
               else twiddle ring lengths position False (layer ring lengths position values)
        (stages,final)=run rest result in ((position,result) :: stages,final)

coordinate : List Integer -> Integer -> Integer -> Integer
coordinate lengths address axis = (address `div` power (axisOffset lengths axis)) `mod` at axis lengths 1
directDFTSum : Integer -> List Integer -> Bool -> A -> A
directDFTSum ring lengths opposite values = map value [(destination,coefficient) | destination <- [0..records lengths-1],coefficient <- [0..ring-1]] where
  value : (Integer,Integer) -> G
  value (destination,coefficient) = gaussianSum (map contribution [0..records lengths-1]) where
    contribution : Integer -> G
    contribution source =
      let exponent=sum [(2*ring `div` size)*coordinate lengths source axis*coordinate lengths destination axis
                        | (axis,size) <- zip (indices lengths) lengths]
          polynomial=[at (source*ring+index) values (0,0) | index <- [0..ring-1]] in
      at coefficient (monomial ring (if opposite then exponent else -exponent) polynomial) (0,0)

squared : G -> Integer
squared (real,imaginary) = real*real+imaginary*imaginary
difference : G -> G -> G
difference first second = add first (scale (-1) second)
assert : Bool -> IO ()
assert True = pure ()
assert False = do putStrLn "FAIL independent direct-value certificate"; exitWith (ExitFailure 10)
checkDFT : Integer -> List Integer -> Bool -> A -> A -> IO ()
checkDFT ring lengths opposite input result = do
  let count=records lengths
  let rounds=foldl max 0 (map logarithm lengths)
  let exact=directDFTSum ring lengths opposite (if opposite then unstore ring lengths input else input)
  let actual=if opposite then result else unstore ring lengths result
  let mismatches = filter (\(index,(computed,ideal)) => squared (difference (scale count computed) ideal) >= 2*rounds*rounds*count*count) (zip (indices actual) (zip actual exact))
  traverse_ (\(index,(computed,ideal)) => putStrLn ("DFT mismatch ring=" ++ show ring ++ " lengths=" ++ show lengths ++ " opposite=" ++ show opposite ++ " index=" ++ show index ++ " grid=" ++ show computed ++ " ideal-sum=" ++ show ideal)) (take 4 mismatches)
  assert (null mismatches)

input : Integer -> Integer -> Integer -> Bool -> Integer -> A
input precision length test convolution second = map value [0..length-1] where
  value : Integer -> G
  value index =
    let base=power precision in
    if not convolution && test<2*length then
      ((if test<length && index==test then base else 0),(if test>=length && index==test-length then base else 0))
    else let denominator=if convolution then 4 else if test==2*length then 2 else base in
      ((((index*7+test*11+second*3) `mod` 3)-1)*(base `div` denominator),
       (((index*11+test*3+second*7) `mod` 3)-1)*(base `div` denominator))

ringProduct : Integer -> A -> A -> A
ringProduct ring first second = map value [0..ring-1] where
  value : Integer -> G
  value destination = gaussianSum (map contribution [0..ring-1]) where
    contribution : Integer -> G
    contribution source =
      let other=residue (destination-source) ring in
      scale (if source+other>=ring then -1 else 1) (multiply (at source first (0,0)) (at other second (0,0)))
evaluation : Integer -> Bool -> A -> Integer
evaluation precision imaginary values = sum [(if imaginary then snd value else fst value)*power (4*precision*index)
  | (index,value) <- zip (the (List Integer) [0..cast (length values)-1]) values]
shortTrace : Integer -> Integer -> Integer -> Integer -> Integer -> A -> A -> IO ()
shortTrace precision ring profile test address first second = do
  let a=evaluation precision False first
  let b=evaluation precision True first
  let c=evaluation precision False second
  let d=evaluation precision True second
  traverse_ (\(index,(left,right)) => putStrLn ("short\t" ++ show precision ++ "\t" ++ show profile ++ "\t" ++ show test ++ "\t" ++ show address ++ "\t" ++ show index ++ "\t" ++ show (bits (abs left)) ++ "\t" ++ show (bits (abs right)) ++ "\t" ++ show (bits (abs (left*right))) ++ "\t" ++ show (4*ring) ++ "\treduced-schoolbook"))
    (zip (the (List Integer) [0..3]) [(a,c),(b,d),(a,d),(b,c)])
subtractAddress : List Integer -> Integer -> Integer -> Integer
subtractAddress lengths destination source = sum [residue (coordinate lengths destination axis-coordinate lengths source axis) size*power (axisOffset lengths axis)
  | (axis,size) <- zip (the (List Integer) [0..cast (length lengths)-1]) lengths]
directConvolutionSum : Integer -> List Integer -> A -> A -> A
directConvolutionSum ring lengths first second = map value [(destination,coefficient) | destination <- [0..records lengths-1],coefficient <- [0..ring-1]] where
  value : (Integer,Integer) -> G
  value (destination,coefficient) = gaussianSum (map contribution [(source,index) | source <- [0..records lengths-1],index <- [0..ring-1]]) where
    contribution : (Integer,Integer) -> G
    contribution (source,index) =
      let other=residue (coefficient-index) ring
          otherAddress=subtractAddress lengths destination source in
      scale (if index+other>=ring then -1 else 1) (multiply (at (source*ring+index) first (0,0)) (at (otherAddress*ring+other) second (0,0)))

transformProfile : Integer -> Integer -> List Integer -> Integer -> IO ()
transformProfile precision ring lengths profile = do
  let length=records lengths*ring
  let tests=if profile<2 then [0..2*length+1] else [2*length,2*length+1]
  traverse_ (\test => do
    let original=input precision length test False 0
    let (forwardStages,forward)=procedure ring lengths False original
    checkDFT ring lengths False original forward
    traverse_ (\(stage,values) => emit "tf-round" precision profile test stage values) forwardStages
    emit "tf-output" precision profile test 0 forward
    let (oppositeStages,opposite)=procedure ring lengths True forward
    checkDFT ring lengths True forward opposite
    traverse_ (\(stage,values) => emit "op-round" precision profile test stage values) oppositeStages
    emit "op-output" precision profile test 0 opposite) tests

convolutionProfile : Integer -> Integer -> List Integer -> Integer -> IO ()
convolutionProfile precision ring lengths profile = traverse_ (\test => do
  let count=records lengths
  let length=count*ring
  let first=input precision length test True 0
  let second=input precision length test True 1
  let (_,left)=procedure ring lengths False first
  let (_,right)=procedure ring lengths False second
  checkDFT ring lengths False first left
  checkDFT ring lengths False second right
  emit "left" precision profile test 0 left
  emit "right" precision profile test 0 right
  let pointwise=concatMap (\address => map (divide (power precision*ring))
        (ringProduct ring (take (cast ring) (drop (cast (address*ring)) left)) (take (cast ring) (drop (cast (address*ring)) right)))) [0..count-1]
  traverse_ (\address => do
    let a=take (cast ring) (drop (cast (address*ring)) left)
    let b=take (cast ring) (drop (cast (address*ring)) right)
    emit "pointwise" precision profile test address (take (cast ring) (drop (cast (address*ring)) pointwise))
    shortTrace precision ring profile test address a b) [0..count-1]
  let (_,opposite)=procedure ring lengths True pointwise
  checkDFT ring lengths True pointwise opposite
  emit "opposite" precision profile test 0 opposite
  let result=map (scale count) opposite
  emit "scale" precision profile test 0 result
  let exact=directConvolutionSum ring lengths first second
  let denominator=power precision*ring*count
  let rounds=foldl max 0 (map logarithm lengths)
  let bound=2*count*count*(3*rounds+1)*(3*rounds+1)*denominator*denominator
  assert (all (\(computed,ideal) => squared (difference (scale denominator computed) ideal)<bound) (zip result exact))
  assert (all (\value => squared value<=power (2*precision)) result)
  emit "convolution" precision profile test 0 result) [0..2]

children : IO ()
children = do
  traverse_ (\(which,p,test) => do
    let uR=(test*7) `mod` 5-2
    let uI=(test*11) `mod` 7-3
    let vR=(test*7+3) `mod` 5-2
    let vI=(test*11+7) `mod` 7-3
    emit "child-forward" (p+2) which test 0 [((uR+vR-uI+vI)*2,(uI+vI+uR-vR)*2),((uR+vR+uI-vI)*2,(uI+vI-uR+vR)*2)]
    emit "child-inverse" (p+2) which test 0 [((uR+vR+uI-vI)*2,(uI+vI-uR+vR)*2),((uR+vR-uI+vI)*2,(uI+vI+uR-vR)*2)]
    emit "child-restored" (p+2) which test 0 [(4*uR,4*uI),(4*vR,4*vI)])
    [(which,p,test) | (which,p) <- zip (the (List Integer) [0..2]) [9,33,101],test <- [0..11]]
  traverse_ (\(ring,exponent) => emit "monomial" 9 ring (exponent+17) 0
    (monomial ring exponent [(index-3,2*index-5) | index <- [0..ring-1]]))
    [(ring,exponent) | ring <- the (List Integer) [2,4,8],exponent <- [-17..17]]

main : IO ()
main = do
  [_,kind] <- getArgs | _ => exitWith (ExitFailure 10)
  case kind of
    "child" => children
    "transform" => do
      transformProfile 9 2 [2,2] 0
      transformProfile 9 4 [4,2] 1
      transformProfile 33 4 [4,2,2] 2
      transformProfile 101 8 [8,4] 3
      transformProfile 9 2 [2,1,2,2] 4
    "convolution" => do
      convolutionProfile 9 2 [2,2] 0
      convolutionProfile 9 4 [4,2] 1
      convolutionProfile 33 4 [4,2,2] 2
      convolutionProfile 101 8 [8,4] 3
      convolutionProfile 9 2 [2,1,2,2] 4
    "refusals" => traverse_ (\(name,status) => putStrLn ("refusal\t" ++ name ++ "\t" ++ show status))
      (the (List (String,Integer)) [("precision-low",3),("precision-high",3),("ring",3),("axis-length",3),("no-axes",3),
       ("record-limit",1),("record-budget",1),("published-fixed",3),("phase-precision",3),("phase-axes",3),("phase-budget",1),
       ("fresh-plan",3),("phase-disk",3),("transform-disk",3),("phase-grid",3),("transform-grid",3),("nonprimary-X",3),
       ("phase-alias",3),("transform-alias",3),("trace-alias",3),("convolution-margin",3),("convolution-provider",3),
       ("convolution-radius",3),("phase-capacity",1),("transform-capacity",1),("packed-precision",3),("packed-ring",3),
       ("packed-alias",3),("packed-capacity",1)])
    _ => exitWith (ExitFailure 10)
