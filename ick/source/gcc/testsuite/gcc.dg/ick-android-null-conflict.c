/* { dg-do compile } */
int * _Nonnull _Nullable conflict; /* { dg-error "conflicting pointer" } */
