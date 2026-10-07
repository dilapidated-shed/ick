#ifndef ICK_A53_KERNELS_H
#define ICK_A53_KERNELS_H
/* Freestanding binary32/LP64 boundary; no host headers in ICK objects. */
_Static_assert(sizeof(float) == 4 && __FLT_MANT_DIG__ == 24, "binary32");
_Static_assert(sizeof(void *) == 8 && sizeof(unsigned) == 4, "AAPCS64 LP64");
_Static_assert(sizeof(long) == 8 && sizeof(double) == 8, "AAPCS64 scalar sizes");
enum { IMAGE_SIDE = 128, RAY_SAMPLES = 28, PIXELS = 128 * 128 };
void scalar_kernel(const float *, float *, unsigned);
void vector_kernel(const float *restrict, const float *restrict,
                   float *restrict, unsigned);
unsigned branch_kernel(const unsigned *, unsigned);
void volume_kernel(float *, float, float);
#endif
