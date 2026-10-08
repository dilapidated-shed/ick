/* { dg-do compile } */
/* { dg-options "-std=gnu17" } */

const char * _Nullable nullable_result (const char * _Nonnull argument);
const char * _Null_unspecified unspecified_result (const char * _Nullable argument);
