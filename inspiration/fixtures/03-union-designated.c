/*
 * Reduction for:
 *   Linux C-SKY memcpy pointer-view unions
 *   ICK imprecise.h float/integer bit-view union
 *
 * This intentionally tests an alternate-member representation view.
 */
_Static_assert(sizeof(float) == sizeof(unsigned int),
               "reduction needs float and unsigned int of equal size");

unsigned int
float_object_bits(float value)
{
    union {
        float value;
        unsigned int bits;
    } view = { .value = value };

    return view.bits;
}

float
float_from_object_bits(unsigned int bits)
{
    union {
        float value;
        unsigned int bits;
    } view = { .bits = bits };

    return view.value;
}
