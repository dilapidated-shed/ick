#include "kernels.h"
/* Four independent recurrences. Compile only this fixture without tree SIMD
   to expose scalar FP scheduling; the volume and vector loops stay enabled. */
void scalar_kernel(const float *input, float *output, unsigned count)
{
    float a = 0.25f, b = 0.5f, c = 0.75f, d = 1.0f;
    for (unsigned index = 0; index < count; ++index) {
        a = a * 0.5f + input[index];
        b = b * 0.25f - input[index];
        c = c * 0.125f + input[index];
        d = d * 0.0625f - input[index];
    }
    output[0] = a; output[1] = b; output[2] = c; output[3] = d;
}
