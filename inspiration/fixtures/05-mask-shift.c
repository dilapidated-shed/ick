/*
 * Reduction for:
 *   Linux FIELD_GET-style GNU-C surface
 *   ICK direct FP8/Circle96 fixed mask/shift operations
 *
 * Test the surface macro and core operation separately.
 */
#define FIELD_GET_LIKE(mask, reg)                                      \
    ({                                                                 \
        typeof(mask) field_mask = (mask);                              \
        typeof(reg) field_reg = (reg);                                 \
        (typeof(mask))((field_reg & field_mask)                        \
            >> __builtin_ctzll((unsigned long long)field_mask));       \
    })

unsigned int
kernel_surface_extract(unsigned int word)
{
    return FIELD_GET_LIKE(0x00000f00u, word);
}

unsigned int
ick_core_e4m3_exponent(unsigned char code)
{
    return ((unsigned int)code >> 3) & 0x0fu;
}

unsigned int
ick_core_circle_third(unsigned char code)
{
    return (unsigned int)code >> 5;
}
