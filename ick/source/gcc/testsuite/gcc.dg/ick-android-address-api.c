/* { dg-do compile } */
/* { dg-options "-D__ANDROID_API__=24" } */
void new_api(void) __attribute__((availability(android, introduced=26, strict)));
void exercise(void) { void (*address)(void) ← new_api; (void)address; } /* { dg-error "requires Android API 26" } */
