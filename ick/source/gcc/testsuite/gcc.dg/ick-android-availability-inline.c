/* { dg-do compile } */
/* { dg-options "-std=gnu17 -D__ANDROID_API__=26" } */

static inline int api26_inline (void)
  __attribute__((availability(android, strict, introduced=26)))
{
  return 26;
}

int
use_api26_inline (void)
{
  return api26_inline ();
}
