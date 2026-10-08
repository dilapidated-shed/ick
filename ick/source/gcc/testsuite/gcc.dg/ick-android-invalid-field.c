/* { dg-do compile } */
void api(void) __attribute__((availability(android, typo=26))); /* { dg-error "invalid Android availability field" } */
