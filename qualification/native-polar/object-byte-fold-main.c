/* Execute the existing two directions of physical object-byte folding. */
extern int semantic_constant_to_object_bytes (void);
extern int object_bytes_to_semantic_constant (void);

int
main (void)
{
  return (semantic_constant_to_object_bytes ()
          && object_bytes_to_semantic_constant ()) ? 0 : 1;
}
