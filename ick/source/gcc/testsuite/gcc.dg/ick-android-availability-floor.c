/* { dg-do compile } */
/* { dg-options "-std=gnu17 -D__ANDROID_API__=25" } */

extern int api26_function (void)
  __attribute__((availability(android, strict, introduced=26)));

int
use_api26_function (void)
{
  return api26_function (); /* { dg-error "unavailable" } */
}
