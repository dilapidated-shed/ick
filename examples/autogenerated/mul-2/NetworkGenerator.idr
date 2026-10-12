module NetworkGenerator
import Data.List
import Data.String
import System
%default covering

record Counts where
  constructor NetworkCounts
  triples, data_pairs, invocations, ground_slots, bit_neighbors, complex_neighbors : Integer
  bit_roles, complex_roles, bit_loss, complex_loss, bit_rank, complex_rank : Integer

choose_three : Integer -> Integer
choose_three count = if count<3 then 0 else count*(count-1)*(count-2) `div` 6

network_counts : Integer -> Counts
network_counts ground_dimension =
  let triples = choose_three ground_dimension
      data_pairs = triples*triples*triples
      invocations = 3*triples*triples
      ground_slots = ground_dimension*ground_dimension*ground_dimension
      bit_neighbors = 3*(ground_dimension-3)*(ground_dimension-4) `div` 2
      complex_neighbors = choose_three (ground_dimension-3)+3*(ground_dimension-3)
      bit_roles = 2*data_pairs+invocations*(triples*bit_neighbors+ground_dimension)
      complex_roles = 2*data_pairs+invocations*(triples*complex_neighbors+ground_dimension+1)
      bit_loss = invocations*ground_dimension*ground_dimension
      complex_loss = invocations*(ground_dimension+1)*ground_dimension in
  NetworkCounts triples data_pairs invocations ground_slots bit_neighbors complex_neighbors
    bit_roles complex_roles bit_loss complex_loss
    (bit_roles*ground_slots-data_pairs+2*bit_loss)
    (complex_roles*ground_slots-2*data_pairs+2*complex_loss)

summary : Integer -> IO ()
summary ground_dimension = do
  let counts = network_counts ground_dimension
  traverse_ (\(name,value) => putStrLn ("count\t" ++ show ground_dimension ++ "\t" ++ name ++ "\t" ++ show value))
    [("triples",counts.triples),("data_pairs",counts.data_pairs),("invocations",counts.invocations),
     ("ground_slots",counts.ground_slots),("bit_neighbors",counts.bit_neighbors),
     ("complex_neighbors",counts.complex_neighbors),("bit_roles",counts.bit_roles),
     ("complex_roles",counts.complex_roles),("bit_loss",counts.bit_loss),("complex_loss",counts.complex_loss),
     ("bit_rank",counts.bit_rank),("complex_rank",counts.complex_rank)]

edge : String -> Integer -> Integer -> Integer -> Integer -> Integer -> String
edge field role tail head rank direction =
  "edge\t" ++ field ++ "\t" ++ show role ++ "\t" ++ show tail ++ "\t" ++ show head ++ "\t" ++ show rank ++ "\t" ++ show direction

stage_ranks : Bool -> String -> Integer -> List Integer
stage_ranks physical_x field stage =
  let previous_dimension = if stage==0 then 1 else if stage==1 then 4 else 16 in
  if physical_x then [(if stage==0 && field=="rational" then 1 else (previous_dimension-1)*3),3,0,0]
  else [0,(previous_dimension-1)*3,0,3]

data_edges : String -> Integer -> List String
data_edges field role =
  let physical_x = role<64
      times = the (List Integer) (if physical_x then [2,3,6,7] else [0,1,4,5])
      stages = concat [map (\time => (stage,time)) times | stage <- [0..2]]
      nodes = (-1) :: map (\(stage,time) => 8*stage+time) stages ++ [24]
      ranks = concatMap (stage_ranks physical_x field) [0..2] ++ [0] in
  [edge field role tail head rank (if rank==0 then 0 else 1) | ((tail,head),rank) <- zip (zip nodes (drop 1 nodes)) ranks]

scratch_edges : String -> Integer -> List String
scratch_edges field role =
  let stride = if field=="rational" then 4 else 17
      invocation = (role-128) `div` stride
      local = (role-128) `mod` stride
      stage = invocation `div` 16
      earlier = if stage==0 then 1 else if stage==1 then 4 else 16
      future = if stage==0 then 16 else if stage==1 then 4 else 1
      side = field=="binary" && local<12
      times = the (List Integer) (if side then [0,2,5,7] else [1,3,4,6])
      nodes = (-1) :: map (\time => 8*stage+time) times ++ [24]
      ranks = if side then [earlier-1,(earlier-1)*3+1,2,1,earlier*4*(future-1)]
                         else [(earlier-1)*4,4,4,4,earlier*4*(future-1)]
      directions = if side then [1,1,1,1,1] else [1,1,-1,1,1] in
  [edge field role tail head rank (if rank==0 then 0 else direction)
    | (((tail,head),rank),direction) <- zip (zip (zip nodes (drop 1 nodes)) ranks) directions]

main : IO ()
main = do
  summary 4
  summary 100
  traverse_ putStrLn (concat [(if role<128 then data_edges field role else scratch_edges field role)
                              | field <- ["rational","binary"],
                                role <- [0..(if field=="rational" then 319 else 943)]])
  traverse_ (\(field,role) =>
    let destination = if role<64 then role+64 else if role<128 then role-64 else role
        sign = if field=="binary" && role>=64 && role<128 then -1 else 1 in
    putStrLn ("endpoint\t" ++ field ++ "\t" ++ show role ++ "\t" ++ show destination ++ "\t" ++ show sign))
    [(field,role) | field <- ["rational","binary"], role <- the (List Integer) [0..(if field=="rational" then 319 else 943)]]
