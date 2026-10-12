module LineReference
import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import System
import Reference
%default covering

Matrix : Type
Matrix = List (List Bounds)

Vector : Type
Vector = List (Bounds,Bounds)

ceilRoot : Integer -> Integer
ceilRoot value = find 1 where
  find : Integer -> Integer
  find root = if root*root>=value then root else find (root+1)

residue : Integer -> Integer -> Integer
residue value modulus = ((value `mod` modulus)+modulus) `mod` modulus

nearest : Integer -> Integer -> Integer -> Integer
nearest source target index = (2*target*index+source) `div` (2*source)

sumBounds : List Bounds -> Bounds
sumBounds = foldl add (Interval 0 0)

matrixProduct : Integer -> Matrix -> Matrix -> Matrix
matrixProduct base first second =
  [[sumBounds (zipWith (productBounds base) row column) | column <- transpose second] | row <- first]

matrixAdd : Bool -> Matrix -> Matrix -> Matrix
matrixAdd negative = zipWith (zipWith (if negative then subtract else add))

identity : Integer -> Integer -> Matrix
identity dimension base =
  [[(if row==column then Interval base base else Interval 0 0)
    | column <- [0..dimension-1]] | row <- [0..dimension-1]]

normUpper : Matrix -> Integer
normUpper matrix = foldl max 0 (map (sum . map upper) matrix)

powerUpper : Integer -> Nat -> Integer -> Integer
powerUpper base Z coefficient = base
powerUpper base (S rest) coefficient = ceilQuotient (powerUpper base rest coefficient*coefficient) base

halfInverse : Integer -> Integer -> Integer -> Matrix -> Matrix
halfInverse base source terms errors =
  let initial = map (map (\value => scaled value 1 2)) (identity source base)
      sum = accumulate (cast (terms-1)) 1 initial initial
      tail = powerUpper base (cast terms) (normUpper errors) in
  map (map (\value => Interval (value.lower-tail) (value.upper+tail))) sum where
  accumulate : Nat -> Integer -> Matrix -> Matrix -> Matrix
  accumulate Z index term sum = sum
  accumulate (S rest) index term sum =
    let next = matrixProduct base errors term in
    accumulate rest (index+1) next (matrixAdd (index `mod` 2==1) sum next)

gaussianMatrix : Integer -> Nat -> Bounds -> Integer -> Integer -> Integer -> Integer -> Matrix
gaussianMatrix base terms pi source target alpha referencePrecision =
  map row [0..target-1] where
  row : Integer -> List Bounds
  row rowIndex =
    let radius = ceilRoot referencePrecision*alpha
        center = source*rowIndex `div` target
        weights = [(residue index source,
          scaled (negativeExponential base terms (scaled pi ((index*target-source*rowIndex)*(index*target-source*rowIndex))
            (alpha*alpha*target*target))) 1 (2*alpha))
          | index <- [center-radius..center+radius], abs (index*target-source*rowIndex)<radius*target] in
    map (\column => let value = sumBounds [weight | (index,weight) <- weights,index==column] in
      Interval value.lower (value.upper+1)) [0..source-1]

errorMatrix : Integer -> Nat -> Bounds -> Integer -> Integer -> Integer -> Integer -> Matrix
errorMatrix base terms pi source target alpha referencePrecision =
  map row [0..source-1] where
  term : Integer -> Integer -> (Integer,Bounds)
  term rowIndex offset =
    let beta = target*rowIndex-source*nearest source target rowIndex
        next = residue (rowIndex+offset) source
        nextBeta = target*next-source*nearest source target next
        stretched = target*offset+beta in
    (next,negativeExponential base terms (scaled pi
      (alpha*alpha*(stretched*stretched-nextBeta*nextBeta)) (source*source)))
  row : Integer -> List Bounds
  row rowIndex =
    let radius = ceilQuotient (ceilRoot referencePrecision) (2*alpha)
        weights = [term rowIndex offset | offset <- [-radius..radius],offset/=0] in
    map (\column => let value = sumBounds [weight | (index,weight) <- weights,index==column] in
      Interval value.lower (value.upper+3)) [0..source-1]

diagonal : Integer -> Nat -> Bounds -> Bounds -> Integer -> Integer -> Integer -> List Bounds
diagonal base terms pi logTwo source target alpha =
  map (\row => let beta = target*row-source*nearest source target row
                   argument = subtract (scaled logTwo (2*alpha*alpha-2) 1) (scaled pi (alpha*alpha*beta*beta) (source*source)) in
    negativeExponential base terms argument) [0..source-1]

inputVector : Integer -> Integer -> Integer -> Integer -> Vector
inputVector base precision length example =
  map (\index => let real = if example<length then (if index==example then 1 else 0) else (index*7+example*3) `mod` 3-1
                     imaginary = if example<length then 0 else (index*11+example*5) `mod` 3-1
                     scale = if example<length then base else if example==length then base `div` 2 else base `div` shiftL 1 (cast precision) in
    (Interval (real*scale) (real*scale),Interval (imaginary*scale) (imaginary*scale))) [0..length-1]

applyMatrix : Integer -> Matrix -> Vector -> Vector
applyMatrix base matrix vector =
  [(sumBounds [productBounds base coefficient real | (coefficient,(real,imaginary)) <- zip row vector],
    sumBounds [productBounds base coefficient imaginary | (coefficient,(real,imaginary)) <- zip row vector]) | row <- matrix]

at : Nat -> List item -> Maybe item
at _ [] = Nothing
at Z (first :: rest) = Just first
at (S position) (first :: rest) = at position rest

applyB0 : Integer -> Matrix -> List Bounds -> Integer -> Integer -> Vector -> Vector
applyB0 base inverse diagonal source target input =
  let selected = [fromMaybe (Interval 0 0,Interval 0 0) (at (cast (nearest source target index)) input) | index <- [0..source-1]]
      intermediate = applyMatrix base inverse selected in
  [(productBounds base coefficient real,productBounds base coefficient imaginary) | (coefficient,(real,imaginary)) <- zip diagonal intermediate]

directFourier : Integer -> Nat -> Bounds -> Integer -> Vector -> Vector
directFourier base terms pi length input =
  [(scaled (sumBounds [subtract (productBounds base rootReal real) (productBounds base rootImaginary imaginary)
      | ((rootReal,rootImaginary),(real,imaginary)) <- zip (roots frequency) input]) 1 length,
    scaled (sumBounds [add (productBounds base rootReal imaginary) (productBounds base rootImaginary real)
      | ((rootReal,rootImaginary),(real,imaginary)) <- zip (roots frequency) input]) 1 length) | frequency <- [0..length-1]] where
  roots : Integer -> Vector
  roots frequency = [rootBounds base terms pi (residue (-index*frequency) length) length | index <- [0..length-1]]

profile : Integer -> Integer -> Integer -> Integer -> IO ()
profile precision source target alpha = do
  let referencePrecision = precision+128
  let base = shiftL 1 (cast referencePrecision)
  let terms = cast (referencePrecision+32)
  let pi = piBounds base terms
  let logTwo = logTwoBounds base terms
  let gaussians = gaussianMatrix base terms pi source target alpha referencePrecision
  let errors = errorMatrix base terms pi source target alpha referencePrecision
  let inverseTerms = ceilQuotient (referencePrecision*source) (alpha*alpha*(target-source))+2
  let inverse = halfInverse base source inverseTerms errors
  let multipliers = diagonal base terms pi logTwo source target alpha
  if normUpper errors>=base `div` 2 then exitWith (ExitFailure 8) else pure ()
  putStrLn ("line-parameter\t" ++ show precision ++ "\t" ++ show source ++ "\t" ++ show target ++ "\t" ++ show alpha ++ "\t" ++
    show (ceilRoot precision*alpha) ++ "\t" ++ show (ceilQuotient (ceilRoot precision) (2*alpha)) ++ "\t" ++
    show (ceilQuotient (precision*source) (alpha*alpha*(target-source))))
  traverse_ (\index => putStrLn ("nearest\t" ++ show precision ++ "\t" ++ show source ++ "\t" ++ show target ++ "\t" ++
    show index ++ "\t" ++ show (nearest source target index))) [0..source-1]
  traverse_ (\direction => do
    let inputLength = if direction==0 then source else target
    traverse_ (\example => do
      let input = inputVector base precision inputLength example
      let output = if direction==0 then applyMatrix base gaussians input else applyB0 base inverse multipliers source target input
      traverse_ (\(index,(real,imaginary)) => putStrLn ("line\t" ++ (if direction==0 then "A" else "B0") ++ "\t" ++
        show precision ++ "\t" ++ show source ++ "\t" ++ show target ++ "\t" ++ show alpha ++ "\t" ++ show example ++ "\t" ++ show index ++ "\t" ++
        show referencePrecision ++ "\t" ++ showBounds real ++ "\t" ++ showBounds imaginary))
          (zip (the (List Integer) [0..cast (length output)-1]) output))
      [0..inputLength+1]) (the (List Integer) [0,1])
  let transformed = directFourier base terms pi source (inputVector base precision source source)
  traverse_ (\index => do
    let (real,imaginary) = fromMaybe (Interval 0 0,Interval 0 0) (at (cast (residue (target*index) source)) transformed)
    putStrLn ("identity\t" ++ show precision ++ "\t" ++ show source ++ "\t" ++ show target ++ "\t" ++ show alpha ++ "\t" ++
      show index ++ "\t" ++ show referencePrecision ++ "\t" ++ showBounds real ++ "\t" ++ showBounds imaginary)) [0..source-1]

boxAddress : Integer -> Integer -> Integer -> Integer -> Integer
boxAddress prefix_index row column tail = ((prefix_index*18+row)*19+column)*3+tail

boxPoint : Vector -> Integer -> Integer -> Integer -> Integer -> (Bounds,Bounds)
boxPoint box prefix_index row column tail = fromMaybe (Interval 0 0,Interval 0 0) (at (cast (boxAddress prefix_index row column tail)) box)

tensorAxis : Integer -> Matrix -> Integer -> Integer -> Bool -> Vector -> Vector
tensorAxis base matrix source target second box =
  [point prefix_index row column tail | prefix_index <- the (List Integer) [0,1],row <- [0..17],column <- [0..18],tail <- [0..2]] where
  point : Integer -> Integer -> Integer -> Integer -> (Bounds,Bounds)
  point prefix_index row column tail =
    let destination = if second then column else row in
    if destination>=target then (Interval 0 0,Interval 0 0) else
      let coefficients = fromMaybe [] (at (cast destination) matrix)
          inputs = [boxPoint box prefix_index (if second then row else index) (if second then index else column) tail | index <- [0..source-1]] in
      (sumBounds [productBounds base coefficient real | (coefficient,(real,imaginary)) <- zip coefficients inputs],
       sumBounds [productBounds base coefficient imaginary | (coefficient,(real,imaginary)) <- zip coefficients inputs])

backwardMatrix : Integer -> Integer -> Integer -> Matrix -> List Bounds -> Matrix
backwardMatrix base source target inverse multipliers =
  [[sumBounds [productBounds base multiplier coefficient
      | (index,coefficient) <- zip (the (List Integer) [0..source-1]) inverseRow,nearest source target index==column]
    | column <- [0..target-1]] | (multiplier,inverseRow) <- zip multipliers inverse]

tensorProfile : IO ()
tensorProfile = do
  let precision = the Integer 101
  let q = precision+128
  let base = shiftL 1 (cast q)
  let terms = cast (q+32)
  let pi = piBounds base terms
  let logTwo = logTwoBounds base terms
  let first = gaussianMatrix base terms pi 12 17 4 q
  let second = gaussianMatrix base terms pi 11 16 4 q
  let firstError = errorMatrix base terms pi 12 17 4 q
  let secondError = errorMatrix base terms pi 11 16 4 q
  if normUpper firstError>=base `div` 2 || normUpper secondError>=base `div` 2 then exitWith (ExitFailure 8) else pure ()
  let firstInverse = halfInverse base 12 (ceilQuotient (q*12) 80+2) firstError
  let secondInverse = halfInverse base 11 (ceilQuotient (q*11) 80+2) secondError
  let firstBackward = backwardMatrix base 12 17 firstInverse (diagonal base terms pi logTwo 12 17 4)
  let secondBackward = backwardMatrix base 11 16 secondInverse (diagonal base terms pi logTwo 11 16 4)
  let input = [initial prefix_index row column tail
               | prefix_index <- the (List Integer) [0,1],row <- [0..17],column <- [0..18],tail <- [0..2]]
  let forward = tensorAxis base second 11 16 True (tensorAxis base first 12 17 False input)
  let backward = tensorAxis base firstBackward 17 12 False (tensorAxis base secondBackward 16 11 True forward)
  traverse_ (\(kind,box) => traverse_ (\(prefix_index,row,column,tail) =>
    let (real,imaginary) = boxPoint box prefix_index row column tail in
    putStrLn ("tensor\t" ++ kind ++ "\t101\t" ++ show prefix_index ++ "\t" ++ show row ++ "\t" ++ show column ++ "\t" ++ show tail ++ "\t" ++
      show q ++ "\t" ++ showBounds real ++ "\t" ++ showBounds imaginary))
    [(prefix_index,row,column,tail) | prefix_index <- the (List Integer) [0,1],row <- [0..17],column <- [0..18],tail <- [0..2]])
    [("A",forward),("B0A",backward)] where
  initial : Integer -> Integer -> Integer -> Integer -> (Bounds,Bounds)
  initial prefix_index row column tail =
    if row>=12 || column>=11 then (Interval 0 0,Interval 0 0) else
      let real = ((prefix_index*31+row*11+column*7+tail*5) `mod` 7-3)*shiftL 1 225
          imaginary = ((prefix_index*13+row*17+column*19+tail*23) `mod` 11-5)*shiftL 1 225 in
      (Interval real real,Interval imaginary imaginary)

main : IO ()
main = do
  profile 101 12 17 4
  profile 128 15 23 5
  profile 256 31 38 6
  tensorProfile
