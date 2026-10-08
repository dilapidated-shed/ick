/* { dg-do compile } */
void api(void) __attribute__((availability(android, introduced=26, strict)));
void exercise(void) { api(); } /* { dg-error "explicit numeric minimum API" } */
