/* { dg-do compile } */
/* { dg-options "-std=c11 -Wall -Wextra -Werror=nonnull" } */
extern int descriptors (int values[_Nonnull 2]);
int application (void) {
  return descriptors ((int *)0); /* { dg-error "null assigned to a _Nonnull pointer" } */
}
