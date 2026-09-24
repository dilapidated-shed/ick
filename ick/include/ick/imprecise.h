#ifndef ICK_IMPRECISE_H
#define ICK_IMPRECISE_H

#include <float.h>
#include <limits.h>
#include <stdint.h>

_Static_assert(CHAR_BIT == 8, "ICK imprecise types require 8-bit bytes");
_Static_assert(sizeof(float) == 4, "ICK imprecise types require binary32-sized float");
_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MAX_EXP == 128
               && FLT_MIN_EXP == -125,
               "ICK imprecise types require IEEE-like binary32 float");
_Static_assert(sizeof(uint32_t) == 4, "ICK imprecise types require 32-bit uint32_t");

typedef struct { uint8_t payload; } E3M2;
typedef struct { uint8_t payload; } E5M3;

_Static_assert(sizeof(E3M2) == 1, "E3M2 storage container must be one byte");
_Static_assert(sizeof(E5M3) == 1, "E5M3 storage container must be one byte");

static inline uint32_t
ick_float_bits(float value)
{
    union { float value; uint32_t bits; } view = { .value = value };
    return view.bits;
}

static inline float
ick_float_from_bits(uint32_t bits)
{
    union { float value; uint32_t bits; } view = { .bits = bits };
    return view.value;
}

static inline E3M2
e3m2_from_code(uint8_t code)
{
    E3M2 value = { (uint8_t)(code & 0x3fu) };
    return value;
}

static inline uint8_t
e3m2_code(E3M2 value)
{
    return (uint8_t)(value.payload & 0x3fu);
}

static inline float
e3m2_to_float(E3M2 value)
{
    static const uint32_t positive_bits[32] = {
        0x00000000u, 0x3d800000u, 0x3e000000u, 0x3e400000u,
        0x3e800000u, 0x3ea00000u, 0x3ec00000u, 0x3ee00000u,
        0x3f000000u, 0x3f200000u, 0x3f400000u, 0x3f600000u,
        0x3f800000u, 0x3fa00000u, 0x3fc00000u, 0x3fe00000u,
        0x40000000u, 0x40200000u, 0x40400000u, 0x40600000u,
        0x40800000u, 0x40a00000u, 0x40c00000u, 0x40e00000u,
        0x41000000u, 0x41200000u, 0x41400000u, 0x41600000u,
        0x41800000u, 0x41a00000u, 0x41c00000u, 0x41e00000u
    };
    uint8_t code = e3m2_code(value);
    uint32_t sign = (uint32_t)(code & 0x20u) << 26;
    return ick_float_from_bits(positive_bits[code & 0x1fu] | sign);
}

static inline E3M2
e3m2_from_float(float value)
{
    static const uint32_t midpoint_bits[31] = {
        0x3d000000u, 0x3dc00000u, 0x3e200000u, 0x3e600000u,
        0x3e900000u, 0x3eb00000u, 0x3ed00000u, 0x3ef00000u,
        0x3f100000u, 0x3f300000u, 0x3f500000u, 0x3f700000u,
        0x3f900000u, 0x3fb00000u, 0x3fd00000u, 0x3ff00000u,
        0x40100000u, 0x40300000u, 0x40500000u, 0x40700000u,
        0x40900000u, 0x40b00000u, 0x40d00000u, 0x40f00000u,
        0x41100000u, 0x41300000u, 0x41500000u, 0x41700000u,
        0x41900000u, 0x41b00000u, 0x41d00000u
    };
    uint32_t bits = ick_float_bits(value);
    uint8_t sign = (uint8_t)(bits >> 31);
    uint32_t magnitude = bits & 0x7fffffffu;
    uint8_t code;

    /* OCP leaves source-NaN conversion implementation-defined.  ICK maps a
       NaN to signed zero so no non-finite value is invented in E3M2. */
    if (magnitude > 0x7f800000u)
        return e3m2_from_code((uint8_t)(sign << 5));

    for (code = 0; code < 31; ++code) {
        uint32_t midpoint = midpoint_bits[code];
        if (magnitude < midpoint
            || (magnitude == midpoint && (code & 1u) == 0))
            return e3m2_from_code((uint8_t)((sign << 5) | code));
    }

    return e3m2_from_code((uint8_t)((sign << 5) | 31u));
}

static inline E5M3
e5m3_from_code(uint8_t code)
{
    E5M3 value = { code };
    return value;
}

static inline uint8_t
e5m3_code(E5M3 value)
{
    return value.payload;
}

static inline int
e5m3_from_float(float value, E5M3 *output)
{
    uint32_t bits = ick_float_bits(value);
    uint32_t exponent = (bits >> 23) & 0xffu;

    /* The published conversion is for positive normal values.  Restrict the
       source exponent so subtracting the bias difference does not wrap the
       eight-bit payload. */
    if (!output || (bits >> 31) != 0 || exponent < 112u || exponent > 143u)
        return 0;

    output->payload = (uint8_t)(((bits - 0x38000000u) >> 20) & 0xffu);
    return 1;
}

static inline float
e5m3_to_float(E5M3 value)
{
    uint32_t bits = ((uint32_t)value.payload << 20) + 0x38080000u;
    return ick_float_from_bits(bits);
}

#endif
