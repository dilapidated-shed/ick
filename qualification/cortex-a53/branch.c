#include "kernels.h"
/* Unsigned wrapping arithmetic is defined. Every indexed load is bounded. */
unsigned branch_kernel(const unsigned *input, unsigned count)
{
    unsigned total = 0;
    for (unsigned index = 0; index < count; ++index) {
        unsigned value = input[index];
        if (value & 1u)
            total += value * 17u + input[(index + 7u) % count];
        else
            total ^= (value >> 3) + input[(index + 3u) % count];
    }
    return total;
}
