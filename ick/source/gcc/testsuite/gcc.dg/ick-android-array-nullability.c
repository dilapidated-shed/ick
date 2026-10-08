/* { dg-do compile } */
/* { dg-options "-std=c11 -Wall -Wextra -Werror" } */
extern int array_parameters (int descriptors[_Nonnull 2],
                             char *arguments[_Nullable],
                             int static_bound[static _Nonnull 2],
                             int qualified[const _Nullable 2]);
