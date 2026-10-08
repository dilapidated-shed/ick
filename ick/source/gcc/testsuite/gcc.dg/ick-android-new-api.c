/* { dg-do compile } */
/* { dg-options "-D__ANDROID_API__=24" } */
void new_api(void) __attribute__((availability(android, introduced=26, strict)));
void exercise(void) { new_api(); } /* { dg-error "requires Android API 26" } */
