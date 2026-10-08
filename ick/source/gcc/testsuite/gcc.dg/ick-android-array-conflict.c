/* { dg-do compile } */
extern int descriptors (int values[_Nonnull _Nullable 2]); /* { dg-error "conflicting pointer nullability" } */
