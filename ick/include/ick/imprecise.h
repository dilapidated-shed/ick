#ifndef ICK_IMPRECISE_H
#define ICK_IMPRECISE_H

_Static_assert(__CHAR_BIT__ == 8, "ICK imprecise types require 8-bit bytes");
_Static_assert(__SIZEOF_FLOAT__ == 4, "ICK imprecise types require binary32-sized float");
_Static_assert(__FLT_RADIX__ == 2 && __FLT_MANT_DIG__ == 24
               && __FLT_MAX_EXP__ == 128 && __FLT_MIN_EXP__ == -125,
               "ICK imprecise types require IEEE-like binary32 float");
_Static_assert(sizeof(__UINT32_TYPE__) == 4,
               "ICK imprecise types require a 32-bit unsigned integer type");
_Static_assert(sizeof(__UINT64_TYPE__) == 8 && sizeof(__INT64_TYPE__) == 8,
               "ICK imprecise types require 64-bit integer types");

typedef unsigned char ick_byte;
typedef unsigned short ick_u16;
typedef __UINT32_TYPE__ ick_u32;
typedef __UINT64_TYPE__ ick_u64;
typedef __INT64_TYPE__ ick_i64;

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

static inline int
ick_half_is_nan(ick_u16 code)
{
    return (code & 0x7c00u) == 0x7c00u && (code & 0x03ffu) != 0;
}

static inline int
ick_half_is_infinite(ick_u16 code)
{
    return (code & 0x7fffu) == 0x7c00u;
}

static inline int
ick_half_is_zero(ick_u16 code)
{
    return (code & 0x7fffu) == 0;
}

static inline int
ick_half_sign(ick_u16 code)
{
    return (code & 0x8000u) != 0;
}

static inline unsigned
ick_highest_bit_u64(ick_u64 value)
{
    unsigned result = 0;
    while ((value >>= 1) != 0)
        ++result;
    return result;
}

static inline ick_u64
ick_round_shift_right_even(ick_u64 value, unsigned shift)
{
    ick_u64 quotient;
    ick_u64 remainder;
    ick_u64 halfway;

    if (shift == 0)
        return value;
    if (shift > 64)
        return 0;
    if (shift == 64)
        return value > (ick_u64)0x8000000000000000ULL ? 1u : 0u;

    quotient = value >> shift;
    remainder = value & (((ick_u64)1u << shift) - 1u);
    halfway = (ick_u64)1u << (shift - 1u);
    if (remainder > halfway
        || (remainder == halfway && (quotient & 1u) != 0))
        ++quotient;
    return quotient;
}

static inline ick_u16
ick_half_encode_dyadic(int sign, ick_u64 magnitude, int exponent)
{
    ick_u16 sign_code = sign ? 0x8000u : 0u;
    int top;

    if (magnitude == 0)
        return sign_code;

    top = (int)ick_highest_bit_u64(magnitude) + exponent;
    if (top >= -14) {
        int shift = (int)ick_highest_bit_u64(magnitude) - 10;
        ick_u64 significand = shift > 0
            ? ick_round_shift_right_even(magnitude, (unsigned)shift)
            : magnitude << (unsigned)(-shift);
        int result_exponent = top;

        if (significand >= 2048u) {
            significand >>= 1;
            ++result_exponent;
        }
        if (result_exponent > 15)
            return (ick_u16)(sign_code | 0x7c00u);
        return (ick_u16)(sign_code
            | (ick_u16)((result_exponent + 15) << 10)
            | (ick_u16)(significand - 1024u));
    }

    {
        int shift = exponent + 24;
        ick_u64 mantissa = shift >= 0
            ? magnitude << (unsigned)shift
            : ick_round_shift_right_even(magnitude, (unsigned)(-shift));
        if (mantissa == 0)
            return sign_code;
        if (mantissa >= 1024u)
            return (ick_u16)(sign_code | 0x0400u);
        return (ick_u16)(sign_code | (ick_u16)mantissa);
    }
}

static inline void
ick_half_decode_finite(ick_u16 code, ick_u64 *significand, int *exponent)
{
    ick_u32 encoded_exponent = (code >> 10) & 0x1fu;
    ick_u32 mantissa = code & 0x03ffu;
    if (encoded_exponent == 0) {
        *significand = mantissa;
        *exponent = -24;
    }
    else {
        *significand = 1024u + mantissa;
        *exponent = (int)encoded_exponent - 25;
    }
}

static inline ick_u64
ick_half_fixed_units(ick_u16 code)
{
    ick_u64 significand;
    int exponent;
    ick_half_decode_finite(code, &significand, &exponent);
    if (significand == 0)
        return 0;
    return significand << (unsigned)(exponent + 24);
}

static inline ick_u16
ick_half_add_codes(ick_u16 left, ick_u16 right, int subtract)
{
    const ick_u16 qnan = 0x7e00u;
    ick_i64 left_fixed;
    ick_i64 right_fixed;
    ick_i64 sum;
    int sign;
    ick_u64 magnitude;

    if (ick_half_is_nan(left) || ick_half_is_nan(right))
        return qnan;
    if (subtract)
        right ^= 0x8000u;

    if (ick_half_is_infinite(left) || ick_half_is_infinite(right)) {
        if (ick_half_is_infinite(left) && ick_half_is_infinite(right)
            && ick_half_sign(left) != ick_half_sign(right))
            return qnan;
        return ick_half_is_infinite(left) ? left : right;
    }

    left_fixed = (ick_i64)ick_half_fixed_units(left);
    right_fixed = (ick_i64)ick_half_fixed_units(right);
    if (ick_half_sign(left))
        left_fixed = -left_fixed;
    if (ick_half_sign(right))
        right_fixed = -right_fixed;
    sum = left_fixed + right_fixed;

    if (sum == 0) {
        int negative_zero = ick_half_is_zero(left) && ick_half_is_zero(right)
            && ick_half_sign(left) && ick_half_sign(right);
        return negative_zero ? 0x8000u : 0u;
    }

    sign = sum < 0;
    magnitude = sign ? (ick_u64)(-sum) : (ick_u64)sum;
    return ick_half_encode_dyadic(sign, magnitude, -24);
}

static inline ick_u16
ick_half_multiply_codes(ick_u16 left, ick_u16 right)
{
    const ick_u16 qnan = 0x7e00u;
    int sign = ick_half_sign(left) != ick_half_sign(right);
    ick_u64 left_significand;
    ick_u64 right_significand;
    int left_exponent;
    int right_exponent;

    if (ick_half_is_nan(left) || ick_half_is_nan(right))
        return qnan;
    if ((ick_half_is_infinite(left) && ick_half_is_zero(right))
        || (ick_half_is_infinite(right) && ick_half_is_zero(left)))
        return qnan;
    if (ick_half_is_infinite(left) || ick_half_is_infinite(right))
        return (ick_u16)((sign ? 0x8000u : 0u) | 0x7c00u);
    if (ick_half_is_zero(left) || ick_half_is_zero(right))
        return sign ? 0x8000u : 0u;

    ick_half_decode_finite(
        left, &left_significand, &left_exponent);
    ick_half_decode_finite(
        right, &right_significand, &right_exponent);
    return ick_half_encode_dyadic(
        sign,
        left_significand * right_significand,
        left_exponent + right_exponent);
}

static inline ick_u16
ick_half_divide_codes(ick_u16 left, ick_u16 right)
{
    const ick_u16 qnan = 0x7e00u;
    int sign = ick_half_sign(left) != ick_half_sign(right);
    ick_u16 signed_zero = sign ? 0x8000u : 0u;
    ick_u16 signed_infinity = (ick_u16)(signed_zero | 0x7c00u);
    ick_u64 left_significand;
    ick_u64 right_significand;
    ick_u32 numerator;
    ick_u32 denominator;
    int left_exponent;
    int right_exponent;
    int exponent;

    if (ick_half_is_nan(left) || ick_half_is_nan(right))
        return qnan;
    if ((ick_half_is_infinite(left) && ick_half_is_infinite(right))
        || (ick_half_is_zero(left) && ick_half_is_zero(right)))
        return qnan;
    if (ick_half_is_infinite(left))
        return signed_infinity;
    if (ick_half_is_infinite(right))
        return signed_zero;
    if (ick_half_is_zero(right))
        return signed_infinity;
    if (ick_half_is_zero(left))
        return signed_zero;

    ick_half_decode_finite(left, &left_significand, &left_exponent);
    ick_half_decode_finite(right, &right_significand, &right_exponent);
    numerator = (ick_u32)left_significand;
    denominator = (ick_u32)right_significand;
    exponent = left_exponent - right_exponent;

    while (numerator < denominator) {
        numerator <<= 1;
        --exponent;
    }
    while (numerator >= (denominator << 1)) {
        denominator <<= 1;
        ++exponent;
    }

    if (exponent >= -14) {
        ick_u32 scaled = numerator << 10;
        ick_u32 quotient = scaled / denominator;
        ick_u32 remainder = scaled % denominator;
        ick_u32 twice_remainder = remainder << 1;
        if (twice_remainder > denominator
            || (twice_remainder == denominator && (quotient & 1u) != 0))
            ++quotient;
        if (quotient >= 2048u) {
            quotient >>= 1;
            ++exponent;
        }
        if (exponent > 15)
            return signed_infinity;
        if (exponent >= -14)
            return (ick_u16)(signed_zero
                | (ick_u16)((exponent + 15) << 10)
                | (ick_u16)(quotient - 1024u));
    }

    {
        int shift = exponent + 24;
        ick_u32 scaled_numerator = numerator;
        ick_u32 scaled_denominator = denominator;
        ick_u32 mantissa;
        ick_u32 remainder;
        ick_u32 twice_remainder;

        if (shift >= 0)
            scaled_numerator <<= (unsigned)shift;
        else
            scaled_denominator <<= (unsigned)(-shift);

        mantissa = scaled_numerator / scaled_denominator;
        remainder = scaled_numerator % scaled_denominator;
        twice_remainder = remainder << 1;
        if (twice_remainder > scaled_denominator
            || (twice_remainder == scaled_denominator && (mantissa & 1u) != 0))
            ++mantissa;
        if (mantissa == 0)
            return signed_zero;
        if (mantissa >= 1024u)
            return (ick_u16)(signed_zero | 0x0400u);
        return (ick_u16)(signed_zero | (ick_u16)mantissa);
    }
}

static inline Float16 float16_add(Float16 a, Float16 b)
{ return float16_from_code(ick_half_add_codes(a.payload, b.payload, 0)); }
static inline Float16 float16_subtract(Float16 a, Float16 b)
{ return float16_from_code(ick_half_add_codes(a.payload, b.payload, 1)); }
static inline Float16 float16_multiply(Float16 a, Float16 b)
{ return float16_from_code(ick_half_multiply_codes(a.payload, b.payload)); }
static inline Float16 float16_divide(Float16 a, Float16 b)
{ return float16_from_code(ick_half_divide_codes(a.payload, b.payload)); }

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
        return e3m2_from_code(0);
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

/* Checked E5M3 arithmetic stays in the E5M3 dyadic lattice.  Addition and
   subtraction use an exact common fixed-point scale. Multiplication widens
   only its integer significand product, then immediately requantizes. */
static inline ick_u64
ick_e5m3_significand(E5M3 value)
{
    return 17u + 2u * (ick_u64)(value.payload & 0x07u);
}

static inline int
ick_e5m3_exponent(E5M3 value)
{
    return (int)(value.payload >> 3) - 19;
}

static inline ick_u64
ick_e5m3_fixed_units(E5M3 value)
{
    return ick_e5m3_significand(value) << (unsigned)(value.payload >> 3);
}

static inline int
ick_e5m3_from_dyadic(ick_u64 magnitude, int exponent, E5M3 *output)
{
    unsigned source_top;
    int result_exponent;
    unsigned mantissa;

    if (!output || magnitude == 0)
        return 0;

    source_top = ick_highest_bit_u64(magnitude);
    result_exponent = (int)source_top + exponent;
    if (result_exponent < -15 || result_exponent > 16)
        return 0;

    mantissa = source_top >= 3
        ? (unsigned)((magnitude >> (source_top - 3u)) & 0x07u)
        : (unsigned)((magnitude << (3u - source_top)) & 0x07u);
    output->payload = (ick_byte)(((result_exponent + 15) << 3) | mantissa);
    return 1;
}

static inline int
e5m3_add(E5M3 left, E5M3 right, E5M3 *output)
{
    E5M3 candidate;
    if (!ick_e5m3_from_dyadic(
            ick_e5m3_fixed_units(left) + ick_e5m3_fixed_units(right),
            -19, &candidate))
        return 0;
    if (output)
        *output = candidate;
    return output != 0;
}

static inline int
e5m3_subtract(E5M3 left, E5M3 right, E5M3 *output)
{
    ick_u64 left_units = ick_e5m3_fixed_units(left);
    ick_u64 right_units = ick_e5m3_fixed_units(right);
    E5M3 candidate;
    if (!output || left_units <= right_units)
        return 0;
    if (!ick_e5m3_from_dyadic(left_units - right_units, -19, &candidate))
        return 0;
    *output = candidate;
    return 1;
}

static inline int
e5m3_multiply(E5M3 left, E5M3 right, E5M3 *output)
{
    E5M3 candidate;
    if (!output || !ick_e5m3_from_dyadic(
            ick_e5m3_significand(left) * ick_e5m3_significand(right),
            ick_e5m3_exponent(left) + ick_e5m3_exponent(right),
            &candidate))
        return 0;
    *output = candidate;
    return 1;
}

#endif
