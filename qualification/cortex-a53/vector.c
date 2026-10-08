#include "kernels.h"
/* Independent outputs, no reassociation of a floating-point reduction.
   restrict is satisfied by the harness's distinct arrays. */
void vector_kernel(const float *restrict left, const float *restrict right,
                   float *restrict output, unsigned count)
{
    for (unsigned index = 0; index < count; ++index)
        output[index] = (left[index] * 0.5f + right[index]) * 0.25f;
}
