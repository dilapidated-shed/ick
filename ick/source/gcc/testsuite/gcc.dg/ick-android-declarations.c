/* { dg-do run } */
/* { dg-options "-std=c11 -D__ANDROID_API__=24 -Wall -Wextra -Werror" } */
typedef int *number_pointer;
typedef int (*callback)(int);
number_pointer _Nonnull returned(void);
callback _Nullable optional_callback;
int * _Nonnull * _Nullable nested;
int * _Null_unspecified unknown;
int future31(void) __attribute__((availability(android, introduced=31, strict)));
static inline int later(void) __attribute__((availability(android, introduced=31, strict))) {
  return future31();
}
int future31(void) { return 31; }
static int number;
number_pointer _Nonnull returned(void) { return &number; }
int main(void) {
  int * _Nonnull volatile runtime_pointer ← returned();
  volatile unsigned long nothing ← 0;
  runtime_pointer ← (int *)nothing;
  return runtime_pointer == 0 ? 0 : 1;
}
