/* Do not erase this annotation: it enforces the application's minimum API.
   The postfix placement is the form used by Android inline declarations. */
static inline int
bionic_api_boundary(void)
  __attribute__((availability(android, strict, introduced=26)))
{
  return 26;
}

int
bionic_use_api_boundary(void)
{
  return bionic_api_boundary();
}
