/* { dg-do compile } */
/* { dg-options "-Werror=nonnull" } */
void required(int * _Nonnull value);
void exercise(void) { required(0); } /* { dg-error "null assigned" } */
