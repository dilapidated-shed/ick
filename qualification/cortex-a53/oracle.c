#include "kernels.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
static float image[3 * PIXELS], input[259], right[259], output[259];
static unsigned loads[259];
static uint32_t bits(float value) { uint32_t result; memcpy(&result, &value, 4); return result; }
static uint64_t digest(const float *values, unsigned count)
{
    uint64_t result = UINT64_C(14695981039346656037);
    for (unsigned index = 0; index < count; ++index) {
        uint32_t word = bits(values[index]);
        for (unsigned byte = 0; byte < 4; ++byte) {
            result ^= (word >> (8 * byte)) & 255u;
            result *= UINT64_C(1099511628211);
        }
    }
    return result;
}
int main(void)
{
    for (unsigned index = 0; index < 259; ++index) {
        input[index] = (float)((int)(index % 17) - 8) * 0.125f;
        right[index] = (float)(index % 13) * 0.0625f;
        loads[index] = index * 2654435761u;
    }
    float scalar[4];
    scalar_kernel(input, scalar, 259);
    /* Deliberately different loop organization from the four-stream kernel. */
    for (unsigned stream = 0; stream < 4; ++stream) {
        float expected = (float)(stream + 1) * 0.25f;
        const float scale[] = {0.5f, 0.25f, 0.125f, 0.0625f};
        for (unsigned index = 0; index < 259; ++index)
            expected = expected * scale[stream] +
                ((stream & 1u) ? -input[index] : input[index]);
        if (bits(expected) != bits(scalar[stream])) return 11;
    }
    vector_kernel(input, right, output, 259);
    for (unsigned index = 0; index < 259; ++index) {
        /* Dyadic input makes this independent double oracle exactly rounded. */
        float expected = (float)(((double)input[index] * 0.5 + right[index]) * 0.25);
        if (bits(expected) != bits(output[index])) return 12;
    }
    /* Test exceptional IEEE values and tail lengths without prescribing NaN bits. */
    input[0] = -0.0f; right[0] = -0.0f;
    input[1] = INFINITY; right[1] = 1.0f;
    input[2] = NAN; right[2] = 1.0f;
    input[3] = 0x1p-148f; right[3] = 0.0f;
    vector_kernel(input, right, output, 7);
    if (bits(output[0]) != 0x80000000u || !isinf(output[1]) ||
        !isnan(output[2]) || bits(output[3]) != 0) return 13;
    unsigned expected_branch = 0;
    for (unsigned index = 0; index < 259; ++index) {
        if ((loads[index] % 2u) != 0)
            expected_branch += loads[index] * 17u + loads[(index + 7u) % 259u];
        else
            expected_branch ^= loads[index] / 8u + loads[(index + 3u) % 259u];
    }
    if (branch_kernel(loads, 259) != expected_branch) return 14;
    if (branch_kernel(loads, 0) != 0) return 15;
    volume_kernel(image, 0.75f, 0.875f);
    uint64_t image_hash = digest(image, 3 * PIXELS);
    printf("scalar\t%016llx\nvector\t%016llx\nbranch\t%08x\nvolume\t%016llx\n",
           (unsigned long long)digest(scalar, 4),
           (unsigned long long)digest(output, 7), expected_branch,
           (unsigned long long)image_hash);
    /* Frozen only after host -O0 reference run; generation is documented. */
    if (image_hash != UINT64_C(0x433c7e24606b1dbd)) return 16;
    return 0;
}
