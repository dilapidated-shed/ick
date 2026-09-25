#ifndef ICK_IMPRECISE_H
#define ICK_IMPRECISE_H

_Static_assert(__CHAR_BIT__ == 8, "ICK imprecise types require 8-bit bytes");
_Static_assert(__SIZEOF_FLOAT__ == 4, "ICK imprecise types require binary32-sized float");
_Static_assert(__FLT_RADIX__ == 2 && __FLT_MANT_DIG__ == 24
               && __FLT_MAX_EXP__ == 128 && __FLT_MIN_EXP__ == -125,
               "ICK imprecise types require IEEE-like binary32 float");
_Static_assert(sizeof(__UINT32_TYPE__) == 4,
               "ICK imprecise types require a 32-bit unsigned integer type");

typedef unsigned char ick_byte;
typedef unsigned short ick_u16;
typedef __UINT32_TYPE__ ick_u32;

typedef struct { ick_u16 payload; } Float16;
typedef struct { ick_byte payload; } E4M3;
typedef struct { ick_byte payload; } E5M2;
typedef struct { ick_byte payload; } E3M2;
typedef struct { ick_byte payload; } E5M3;

_Static_assert(sizeof(Float16) == 2, "Float16 storage must be two bytes");
_Static_assert(sizeof(E4M3) == 1, "E4M3 storage must be one byte");
_Static_assert(sizeof(E5M2) == 1, "E5M2 storage must be one byte");
_Static_assert(sizeof(E3M2) == 1, "E3M2 storage must be one byte");
_Static_assert(sizeof(E5M3) == 1, "E5M3 storage must be one byte");

static inline ick_u32
ick_float_bits(float value)
{
    union { float value; ick_u32 bits; } view = { .value = value };
    return view.bits;
}

static inline float
ick_float_from_bits(ick_u32 bits)
{
    union { float value; ick_u32 bits; } view = { .bits = bits };
    return view.value;
}

static inline int
ick_float_bits_are_nan(ick_u32 bits)
{
    return (bits & 0x7f800000u) == 0x7f800000u
        && (bits & 0x007fffffu) != 0;
}

/* IEEE binary16 ---------------------------------------------------------- */

static inline Float16
float16_from_code(ick_u16 code)
{
    Float16 value = { code };
    return value;
}

static inline ick_u16
float16_code(Float16 value)
{
    return value.payload;
}

static inline Float16
float16_from_float(float value)
{
    ick_u32 bits = ick_float_bits(value);
    ick_u16 sign = (ick_u16)((bits >> 16) & 0x8000u);
    ick_u32 exponent = (bits >> 23) & 0xffu;
    ick_u32 mantissa = bits & 0x007fffffu;

    if (exponent == 0xffu) {
        if (mantissa == 0)
            return float16_from_code((ick_u16)(sign | 0x7c00u));
        return float16_from_code((ick_u16)(sign | 0x7e00u));
    }

    if (exponent == 0)
        return float16_from_code(sign);

    {
        int unbiased = (int)exponent - 127;

        if (unbiased > 15)
            return float16_from_code((ick_u16)(sign | 0x7c00u));

        if (unbiased >= -14) {
            ick_u32 half_exponent = (ick_u32)(unbiased + 15);
            ick_u32 half_mantissa = mantissa >> 13;
            ick_u32 remainder = mantissa & 0x1fffu;

            if (remainder > 0x1000u
                || (remainder == 0x1000u && (half_mantissa & 1u))) {
                ++half_mantissa;
                if (half_mantissa == 0x400u) {
                    half_mantissa = 0;
                    ++half_exponent;
                    if (half_exponent == 0x1fu)
                        return float16_from_code((ick_u16)(sign | 0x7c00u));
                }
            }

            return float16_from_code((ick_u16)(sign
                | (ick_u16)(half_exponent << 10)
                | (ick_u16)half_mantissa));
        }

        if (unbiased < -25)
            return float16_from_code(sign);

        {
            ick_u32 significand = 0x00800000u | mantissa;
            unsigned shift = (unsigned)(-unbiased - 1);
            ick_u32 half_mantissa = significand >> shift;
            ick_u32 mask = ((ick_u32)1u << shift) - 1u;
            ick_u32 remainder = significand & mask;
            ick_u32 halfway = (ick_u32)1u << (shift - 1u);

            if (remainder > halfway
                || (remainder == halfway && (half_mantissa & 1u)))
                ++half_mantissa;

            return float16_from_code((ick_u16)(sign | (ick_u16)half_mantissa));
        }
    }
}

static inline float
float16_to_float(Float16 value)
{
    ick_u16 code = value.payload;
    ick_u32 sign = (ick_u32)(code & 0x8000u) << 16;
    ick_u32 exponent = (code >> 10) & 0x1fu;
    ick_u32 mantissa = code & 0x03ffu;

    if (exponent == 0) {
        if (mantissa == 0)
            return ick_float_from_bits(sign);
        {
            float magnitude = (float)mantissa * ick_float_from_bits(0x33800000u);
            return (code & 0x8000u) ? -magnitude : magnitude;
        }
    }

    if (exponent == 0x1fu)
        return ick_float_from_bits(sign | 0x7f800000u | (mantissa << 13));

    return ick_float_from_bits(sign
        | ((exponent + (127u - 15u)) << 23)
        | (mantissa << 13));
}

static inline Float16 float16_add(Float16 a, Float16 b)
{ return float16_from_float(float16_to_float(a) + float16_to_float(b)); }
static inline Float16 float16_subtract(Float16 a, Float16 b)
{ return float16_from_float(float16_to_float(a) - float16_to_float(b)); }
static inline Float16 float16_multiply(Float16 a, Float16 b)
{ return float16_from_float(float16_to_float(a) * float16_to_float(b)); }
static inline Float16 float16_divide(Float16 a, Float16 b)
{ return float16_from_float(float16_to_float(a) / float16_to_float(b)); }

/* OCP OFP8 E4M3 --------------------------------------------------------- */

static inline E4M3 e4m3_from_code(ick_byte code)
{ E4M3 value = { code }; return value; }
static inline ick_byte e4m3_code(E4M3 value)
{ return value.payload; }

static inline float
e4m3_positive_to_float(ick_byte code)
{
    ick_u32 exponent = (code >> 3) & 0x0fu;
    ick_u32 mantissa = code & 0x07u;
    if (exponent == 0)
        return (float)mantissa * ick_float_from_bits(0x3b000000u);
    if (exponent == 0x0fu && mantissa == 0x07u)
        return ick_float_from_bits(0x7fc00000u);
    return ick_float_from_bits(((exponent + (127u - 7u)) << 23)
                               | (mantissa << 20));
}

static inline float
e4m3_to_float(E4M3 value)
{
    ick_byte code = value.payload;
    float magnitude = e4m3_positive_to_float((ick_byte)(code & 0x7fu));
    return (code & 0x80u) ? -magnitude : magnitude;
}

static inline E4M3
e4m3_from_float(float value)
{
    ick_u32 bits = ick_float_bits(value);
    ick_byte sign = (ick_byte)((bits >> 24) & 0x80u);
    ick_u32 magnitude_bits = bits & 0x7fffffffu;
    ick_byte code;

    if (ick_float_bits_are_nan(bits))
        return e4m3_from_code((ick_byte)(sign | 0x7fu));
    if (magnitude_bits == 0)
        return e4m3_from_code(sign);
    if (magnitude_bits >= ick_float_bits(448.0f))
        return e4m3_from_code((ick_byte)(sign | 0x7eu));

    for (code = 0; code < 0x7eu; ++code) {
        float lower = e4m3_positive_to_float(code);
        float upper = e4m3_positive_to_float((ick_byte)(code + 1u));
        float midpoint = lower + (upper - lower) * 0.5f;
        float magnitude = ick_float_from_bits(magnitude_bits);
        if (magnitude < midpoint
            || (magnitude == midpoint && (code & 1u) == 0))
            return e4m3_from_code((ick_byte)(sign | code));
    }
    return e4m3_from_code((ick_byte)(sign | 0x7eu));
}

static inline E4M3 e4m3_add(E4M3 a, E4M3 b)
{ return e4m3_from_float(e4m3_to_float(a) + e4m3_to_float(b)); }
static inline E4M3 e4m3_subtract(E4M3 a, E4M3 b)
{ return e4m3_from_float(e4m3_to_float(a) - e4m3_to_float(b)); }
static inline E4M3 e4m3_multiply(E4M3 a, E4M3 b)
{ return e4m3_from_float(e4m3_to_float(a) * e4m3_to_float(b)); }
static inline E4M3 e4m3_divide(E4M3 a, E4M3 b)
{ return e4m3_from_float(e4m3_to_float(a) / e4m3_to_float(b)); }

/* OCP OFP8 E5M2 --------------------------------------------------------- */

static inline E5M2 e5m2_from_code(ick_byte code)
{ E5M2 value = { code }; return value; }
static inline ick_byte e5m2_code(E5M2 value)
{ return value.payload; }

static inline float
e5m2_positive_to_float(ick_byte code)
{
    ick_u32 exponent = (code >> 2) & 0x1fu;
    ick_u32 mantissa = code & 0x03u;
    if (exponent == 0)
        return (float)mantissa * ick_float_from_bits(0x37800000u);
    if (exponent == 0x1fu)
        return ick_float_from_bits(0x7f800000u | (mantissa << 21));
    return ick_float_from_bits(((exponent + (127u - 15u)) << 23)
                               | (mantissa << 21));
}

static inline float
e5m2_to_float(E5M2 value)
{
    ick_byte code = value.payload;
    float magnitude = e5m2_positive_to_float((ick_byte)(code & 0x7fu));
    return (code & 0x80u) ? -magnitude : magnitude;
}

static inline E5M2
e5m2_from_float(float value)
{
    ick_u32 bits = ick_float_bits(value);
    ick_byte sign = (ick_byte)((bits >> 24) & 0x80u);
    ick_u32 magnitude_bits = bits & 0x7fffffffu;
    ick_byte code;

    if (ick_float_bits_are_nan(bits))
        return e5m2_from_code((ick_byte)(sign | 0x7fu));
    if (magnitude_bits == 0)
        return e5m2_from_code(sign);
    if (magnitude_bits >= ick_float_bits(57344.0f))
        return e5m2_from_code((ick_byte)(sign | 0x7bu));

    for (code = 0; code < 0x7bu; ++code) {
        float lower = e5m2_positive_to_float(code);
        float upper = e5m2_positive_to_float((ick_byte)(code + 1u));
        float midpoint = lower + (upper - lower) * 0.5f;
        float magnitude = ick_float_from_bits(magnitude_bits);
        if (magnitude < midpoint
            || (magnitude == midpoint && (code & 1u) == 0))
            return e5m2_from_code((ick_byte)(sign | code));
    }
    return e5m2_from_code((ick_byte)(sign | 0x7bu));
}

static inline E5M2 e5m2_add(E5M2 a, E5M2 b)
{ return e5m2_from_float(e5m2_to_float(a) + e5m2_to_float(b)); }
static inline E5M2 e5m2_subtract(E5M2 a, E5M2 b)
{ return e5m2_from_float(e5m2_to_float(a) - e5m2_to_float(b)); }
static inline E5M2 e5m2_multiply(E5M2 a, E5M2 b)
{ return e5m2_from_float(e5m2_to_float(a) * e5m2_to_float(b)); }
static inline E5M2 e5m2_divide(E5M2 a, E5M2 b)
{ return e5m2_from_float(e5m2_to_float(a) / e5m2_to_float(b)); }

/* OCP MX FP6 E3M2 ------------------------------------------------------- */

static inline E3M2 e3m2_from_code(ick_byte code)
{ E3M2 value = { (ick_byte)(code & 0x3fu) }; return value; }
static inline ick_byte e3m2_code(E3M2 value)
{ return (ick_byte)(value.payload & 0x3fu); }

static inline float
e3m2_positive_to_float(ick_byte code)
{
    ick_u32 exponent = (code >> 2) & 0x07u;
    ick_u32 mantissa = code & 0x03u;
    if (exponent == 0)
        return (float)mantissa * 0.0625f;
    return ick_float_from_bits(((exponent + (127u - 3u)) << 23)
                               | (mantissa << 21));
}

static inline float
e3m2_to_float(E3M2 value)
{
    ick_byte code = e3m2_code(value);
    float magnitude = e3m2_positive_to_float((ick_byte)(code & 0x1fu));
    return (code & 0x20u) ? -magnitude : magnitude;
}

static inline E3M2
e3m2_from_float(float value)
{
    ick_u32 bits = ick_float_bits(value);
    ick_byte sign = (ick_byte)((bits >> 26) & 0x20u);
    ick_u32 magnitude_bits = bits & 0x7fffffffu;
    ick_byte code;

    if (ick_float_bits_are_nan(bits))
        return e3m2_from_code(sign);
    if (magnitude_bits == 0)
        return e3m2_from_code(sign);
    if (magnitude_bits >= ick_float_bits(28.0f))
        return e3m2_from_code((ick_byte)(sign | 0x1fu));

    for (code = 0; code < 0x1fu; ++code) {
        float lower = e3m2_positive_to_float(code);
        float upper = e3m2_positive_to_float((ick_byte)(code + 1u));
        float midpoint = lower + (upper - lower) * 0.5f;
        float magnitude = ick_float_from_bits(magnitude_bits);
        if (magnitude < midpoint
            || (magnitude == midpoint && (code & 1u) == 0))
            return e3m2_from_code((ick_byte)(sign | code));
    }
    return e3m2_from_code((ick_byte)(sign | 0x1fu));
}

static inline E3M2 e3m2_add(E3M2 a, E3M2 b)
{ return e3m2_from_float(e3m2_to_float(a) + e3m2_to_float(b)); }
static inline E3M2 e3m2_subtract(E3M2 a, E3M2 b)
{ return e3m2_from_float(e3m2_to_float(a) - e3m2_to_float(b)); }
static inline E3M2 e3m2_multiply(E3M2 a, E3M2 b)
{ return e3m2_from_float(e3m2_to_float(a) * e3m2_to_float(b)); }
static inline E3M2 e3m2_divide(E3M2 a, E3M2 b)
{ return e3m2_from_float(e3m2_to_float(a) / e3m2_to_float(b)); }

/* Ootomo-Naruse unsigned E5M3 storage ---------------------------------- */

static inline E5M3 e5m3_from_code(ick_byte code)
{ E5M3 value = { code }; return value; }
static inline ick_byte e5m3_code(E5M3 value)
{ return value.payload; }

static inline int
e5m3_from_float(float value, E5M3 *output)
{
    ick_u32 bits = ick_float_bits(value);
    ick_u32 exponent = (bits >> 23) & 0xffu;
    if (!output || (bits >> 31) != 0 || exponent < 112u || exponent > 143u)
        return 0;
    output->payload = (ick_byte)(((bits - 0x38000000u) >> 20) & 0xffu);
    return 1;
}

static inline float
e5m3_to_float(E5M3 value)
{
    ick_u32 bits = ((ick_u32)value.payload << 20) + 0x38080000u;
    return ick_float_from_bits(bits);
}

#endif
