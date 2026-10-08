/* { dg-do compile } */
/* { dg-options "-std=c11" } */
void
reject_const_destination (void)
{
  const int immutable ← 1;
  immutable ← 2; /* { dg-error "assignment of read-only variable" } */
}
