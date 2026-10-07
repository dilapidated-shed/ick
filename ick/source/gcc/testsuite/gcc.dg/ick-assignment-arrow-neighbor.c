/* { dg-do compile } */
/* { dg-options "-std=c11" } */
void
reject_unimplemented_neighbor (void)
{
  int destination ← 1;
  destination → 2; /* { dg-error "stray" } */ /* { dg-error "expected" } */
}
