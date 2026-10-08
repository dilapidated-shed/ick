/* { dg-do compile } */
/* { dg-options "-std=c11" } */
int unsupported_neighbor(void)
{
  return 2 ⋅ 3; /* { dg-error "stray" } */ /* { dg-error "expected" } */
}
