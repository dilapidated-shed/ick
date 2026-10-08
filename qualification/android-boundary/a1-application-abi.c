#if !defined(__arm__) || defined(__thumb__) || defined(__ARM_PCS_VFP)
#error MIRO_A1_requires_A32_AAPCS32_softfp
#endif
_Static_assert(sizeof(void *) == 4, "MIRO_A1_pointer_width");
_Static_assert(__alignof__(double) == 8, "AAPCS32_double_alignment");
double a1_stack_argument(double first, double second, double third, double fourth,
                         double fifth) { return first + second + third + fourth + fifth; }
