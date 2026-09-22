/* This translation unit is compiled by a stock target compiler for optional
   non-Android execution. The shared bridge body is also accepted by Android
   NDK Clang. */

extern int wegert_ick_runtime_probe (void);

int
main (void)
{
  return wegert_ick_runtime_probe ();
}
