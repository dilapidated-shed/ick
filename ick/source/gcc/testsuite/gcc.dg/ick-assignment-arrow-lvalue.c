/* { dg-do compile } */
/* { dg-options "-std=c11" } */
void
reject_non_lvalue_destination (void)
{
  3 ← 4; /* { dg-error "lvalue required" } */
}
