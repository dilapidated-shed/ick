/** Compact scalar representations, ported from ick/include/ick/imprecise.h.
 * These are distinct D value types, not integer or float aliases.
 * The portable implementation is a reference follower, not a new backend IR.
 */
module icky.imprecise;

nothrow @nogc:

static assert(float.sizeof == 4 && float.mant_dig == 24);
static assert(uint.sizeof == 4 && ushort.sizeof == 2);

private union FloatBits { float value; uint bits; }
private uint float_bits(float value)
{
    FloatBits view;
    view.value = value;
    return view.bits;
}
private float float_from_bits(uint bits)
{
    FloatBits view;
    view.bits = bits;
    return view.value;
}
private bool is_nan_bits(uint bits)
{
    return (bits & 0x7f800000u) == 0x7f800000u && (bits & 0x007fffffu) != 0;
}

private enum ScalarFormat { binary16, e4m3, e5m2, e3m2 }

private bool half_is_nan(ushort code)
{
    return (code & 0x7c00u) == 0x7c00u && (code & 0x03ffu) != 0;
}
private bool half_is_infinite(ushort code)
{
    return (code & 0x7fffu) == 0x7c00u;
}
private bool half_is_zero(ushort code)
{
    return (code & 0x7fffu) == 0;
}
private bool half_sign(ushort code)
{
    return (code & 0x8000u) != 0;
}
private uint highest_bit(ulong value)
{
    assert(value != 0);
    uint result;
    while ((value >>= 1) != 0) ++result;
    return result;
}
private ulong round_shift_right_even(ulong value, uint shift)
{
    if (shift == 0) return value;
    if (shift > 64) return 0;
    if (shift == 64)
        return value > 0x8000000000000000UL ? 1UL : 0UL;
    ulong quotient = value >> shift;
    ulong remainder = value & ((1UL << shift) - 1UL);
    ulong halfway = 1UL << (shift - 1);
    if (remainder > halfway || (remainder == halfway && (quotient & 1UL) != 0))
        ++quotient;
    return quotient;
}
private ushort half_encode_dyadic(bool sign, ulong magnitude, int exponent)
{
    const ushort signCode = sign ? 0x8000u : 0u;
    if (magnitude == 0) return signCode;

    const int top = cast(int)highest_bit(magnitude) + exponent;
    if (top >= -14)
    {
        const int shift = cast(int)highest_bit(magnitude) - 10;
        ulong significand = shift > 0
            ? round_shift_right_even(magnitude, cast(uint)shift)
            : magnitude << cast(uint)(-shift);
        int resultExponent = top;
        if (significand >= 2048)
        {
            significand >>= 1;
            ++resultExponent;
        }
        if (resultExponent > 15)
            return cast(ushort)(signCode | 0x7c00u);
        return cast(ushort)(
            signCode |
            cast(ushort)((resultExponent + 15) << 10) |
            cast(ushort)(significand - 1024));
    }

    const int subnormalShift = exponent + 24;
    ulong mantissa = subnormalShift >= 0
        ? magnitude << cast(uint)subnormalShift
        : round_shift_right_even(magnitude, cast(uint)(-subnormalShift));
    if (mantissa == 0) return signCode;
    if (mantissa >= 1024)
        return cast(ushort)(signCode | 0x0400u);
    return cast(ushort)(signCode | cast(ushort)mantissa);
}
private void half_decode_finite(ushort code, out ulong significand, out int exponent)
{
    const uint encodedExponent = (code >> 10) & 0x1fu;
    const uint mantissa = code & 0x03ffu;
    if (encodedExponent == 0)
    {
        significand = mantissa;
        exponent = -24;
    }
    else
    {
        significand = 1024u + mantissa;
        exponent = cast(int)encodedExponent - 25;
    }
}
private ulong half_fixed_units(ushort code)
{
    ulong significand;
    int exponent;
    half_decode_finite(code, significand, exponent);
    if (significand == 0) return 0;
    return significand << cast(uint)(exponent + 24);
}
private ushort half_add_codes(ushort left, ushort right, bool subtract)
{
    enum ushort qnan = 0x7e00u;
    if (half_is_nan(left) || half_is_nan(right)) return qnan;
    if (subtract) right ^= 0x8000u;

    if (half_is_infinite(left) || half_is_infinite(right))
    {
        if (half_is_infinite(left) && half_is_infinite(right) &&
            half_sign(left) != half_sign(right))
            return qnan;
        return half_is_infinite(left) ? left : right;
    }

    long leftFixed = cast(long)half_fixed_units(left);
    long rightFixed = cast(long)half_fixed_units(right);
    if (half_sign(left)) leftFixed = -leftFixed;
    if (half_sign(right)) rightFixed = -rightFixed;
    const long sum = leftFixed + rightFixed;
    if (sum == 0)
    {
        const bool negativeZero =
            half_is_zero(left) && half_is_zero(right) &&
            half_sign(left) && half_sign(right);
        return negativeZero ? 0x8000u : 0u;
    }
    const bool sign = sum < 0;
    const ulong magnitude = sign ? cast(ulong)(-sum) : cast(ulong)sum;
    return half_encode_dyadic(sign, magnitude, -24);
}
private ushort half_multiply_codes(ushort left, ushort right)
{
    enum ushort qnan = 0x7e00u;
    const bool sign = half_sign(left) != half_sign(right);
    if (half_is_nan(left) || half_is_nan(right)) return qnan;
    if ((half_is_infinite(left) && half_is_zero(right)) ||
        (half_is_infinite(right) && half_is_zero(left)))
        return qnan;
    if (half_is_infinite(left) || half_is_infinite(right))
        return cast(ushort)((sign ? 0x8000u : 0u) | 0x7c00u);
    if (half_is_zero(left) || half_is_zero(right))
        return sign ? 0x8000u : 0u;

    ulong leftSignificand;
    ulong rightSignificand;
    int leftExponent;
    int rightExponent;
    half_decode_finite(left, leftSignificand, leftExponent);
    half_decode_finite(right, rightSignificand, rightExponent);
    return half_encode_dyadic(
        sign, leftSignificand * rightSignificand,
        leftExponent + rightExponent);
}
private ushort half_divide_codes(ushort left, ushort right)
{
    enum ushort qnan = 0x7e00u;
    const bool sign = half_sign(left) != half_sign(right);
    const ushort signedZero = sign ? 0x8000u : 0u;
    const ushort signedInfinity = cast(ushort)(signedZero | 0x7c00u);

    if (half_is_nan(left) || half_is_nan(right)) return qnan;
    if ((half_is_infinite(left) && half_is_infinite(right)) ||
        (half_is_zero(left) && half_is_zero(right)))
        return qnan;
    if (half_is_infinite(left)) return signedInfinity;
    if (half_is_infinite(right)) return signedZero;
    if (half_is_zero(right)) return signedInfinity;
    if (half_is_zero(left)) return signedZero;

    ulong numerator;
    ulong denominator;
    int leftExponent;
    int rightExponent;
    half_decode_finite(left, numerator, leftExponent);
    half_decode_finite(right, denominator, rightExponent);
    int exponent = leftExponent - rightExponent;

    while (numerator < denominator)
    {
        numerator <<= 1;
        --exponent;
    }
    while (numerator >= (denominator << 1))
    {
        denominator <<= 1;
        ++exponent;
    }

    if (exponent >= -14)
    {
        const ulong scaled = numerator << 10;
        ulong quotient = scaled / denominator;
        const ulong remainder = scaled % denominator;
        const ulong twiceRemainder = remainder << 1;
        if (twiceRemainder > denominator ||
            (twiceRemainder == denominator && (quotient & 1UL) != 0))
            ++quotient;
        if (quotient >= 2048)
        {
            quotient >>= 1;
            ++exponent;
        }
        if (exponent > 15) return signedInfinity;
        if (exponent >= -14)
            return cast(ushort)(
                signedZero |
                cast(ushort)((exponent + 15) << 10) |
                cast(ushort)(quotient - 1024));
    }

    const int shift = exponent + 24;
    ulong scaledNumerator = numerator;
    ulong scaledDenominator = denominator;
    if (shift >= 0) scaledNumerator <<= cast(uint)shift;
    else scaledDenominator <<= cast(uint)(-shift);

    ulong mantissa = scaledNumerator / scaledDenominator;
    const ulong remainder = scaledNumerator % scaledDenominator;
    const ulong twiceRemainder = remainder << 1;
    if (twiceRemainder > scaledDenominator ||
        (twiceRemainder == scaledDenominator && (mantissa & 1UL) != 0))
        ++mantissa;
    if (mantissa == 0) return signedZero;
    if (mantissa >= 1024)
        return cast(ushort)(signedZero | 0x0400u);
    return cast(ushort)(signedZero | cast(ushort)mantissa);
}

private ushort encode_half(float value)
{
    uint bits = float_bits(value);
    ushort sign = cast(ushort)((bits >> 16) & 0x8000u);
    uint exponent = (bits >> 23) & 0xffu;
    uint mantissa = bits & 0x007fffffu;
    if (exponent == 0xffu)
        return cast(ushort)(sign | (mantissa == 0 ? 0x7c00u : 0x7e00u));
    if (exponent == 0) return sign;
    int unbiased = cast(int)exponent - 127;
    if (unbiased > 15) return cast(ushort)(sign | 0x7c00u);
    if (unbiased >= -14)
    {
        uint half_exponent = cast(uint)(unbiased + 15);
        uint half_mantissa = mantissa >> 13;
        uint remainder = mantissa & 0x1fffu;
        if (remainder > 0x1000u || (remainder == 0x1000u && (half_mantissa & 1u)))
        {
            ++half_mantissa;
            if (half_mantissa == 0x400u)
            {
                half_mantissa = 0;
                ++half_exponent;
                if (half_exponent == 0x1fu) return cast(ushort)(sign | 0x7c00u);
            }
        }
        return cast(ushort)(sign | (half_exponent << 10) | half_mantissa);
    }
    if (unbiased < -25) return sign;
    uint significand = 0x00800000u | mantissa;
    uint shift = cast(uint)(-unbiased - 1);
    uint half_mantissa = significand >> shift;
    uint remainder = significand & ((1u << shift) - 1u);
    uint halfway = 1u << (shift - 1u);
    if (remainder > halfway || (remainder == halfway && (half_mantissa & 1u)))
        ++half_mantissa;
    return cast(ushort)(sign | half_mantissa);
}

private float decode_half(ushort code)
{
    uint sign = cast(uint)(code & 0x8000u) << 16;
    uint exponent = (code >> 10) & 0x1fu;
    uint mantissa = code & 0x03ffu;
    if (exponent == 0)
    {
        if (mantissa == 0) return float_from_bits(sign);
        float magnitude = cast(float)mantissa * float_from_bits(0x33800000u);
        return (code & 0x8000u) ? -magnitude : magnitude;
    }
    if (exponent == 0x1fu)
        return float_from_bits(sign | 0x7f800000u | (mantissa << 13));
    return float_from_bits(sign | ((exponent + 112u) << 23) | (mantissa << 13));
}

private float decode_positive(ScalarFormat format)(ubyte code)
{
    static if (format == ScalarFormat.e4m3)
    {
        uint exponent = (code >> 3) & 15u;
        uint mantissa = code & 7u;
        if (exponent == 0) return cast(float)mantissa * float_from_bits(0x3b000000u);
        if (exponent == 15u && mantissa == 7u) return float_from_bits(0x7fc00000u);
        return float_from_bits(((exponent + 120u) << 23) | (mantissa << 20));
    }
    else static if (format == ScalarFormat.e5m2)
    {
        uint exponent = (code >> 2) & 31u;
        uint mantissa = code & 3u;
        if (exponent == 0) return cast(float)mantissa * float_from_bits(0x37800000u);
        if (exponent == 31u) return float_from_bits(0x7f800000u | (mantissa << 21));
        return float_from_bits(((exponent + 112u) << 23) | (mantissa << 21));
    }
    else
    {
        uint exponent = (code >> 2) & 7u;
        uint mantissa = code & 3u;
        if (exponent == 0) return cast(float)mantissa * 0.0625f;
        return float_from_bits(((exponent + 124u) << 23) | (mantissa << 21));
    }
}

private ubyte encode_small(ScalarFormat format)(float value)
{
    uint bits = float_bits(value);
    uint magnitude_bits = bits & 0x7fffffffu;
    static if (format == ScalarFormat.e3m2)
    {
        enum uint sign_shift = 26;
        enum uint sign_mask = 0x20;
        enum uint last_code = 0x1f;
        enum float largest = 28.0f;
    }
    else
    {
        enum uint sign_shift = 24;
        enum uint sign_mask = 0x80;
        static if (format == ScalarFormat.e4m3)
        {
            enum uint last_code = 0x7e;
            enum float largest = 448.0f;
        }
        else
        {
            enum uint last_code = 0x7b;
            enum float largest = 57344.0f;
        }
    }
    uint sign = (bits >> sign_shift) & sign_mask;
    if (is_nan_bits(bits))
    {
        static if (format == ScalarFormat.e3m2) return 0;
        else return cast(ubyte)(sign | 0x7fu);
    }
    if (magnitude_bits == 0) return cast(ubyte)sign;
    if (magnitude_bits >= float_bits(largest)) return cast(ubyte)(sign | last_code);
    float magnitude = float_from_bits(magnitude_bits);
    // Keep the existing reference quantizer: nearest with ties to even.
    for (uint code = 0; code < last_code; ++code)
    {
        float lower = decode_positive!format(cast(ubyte)code);
        float upper = decode_positive!format(cast(ubyte)(code + 1u));
        float midpoint = lower + (upper - lower) * 0.5f;
        if (magnitude < midpoint || (magnitude == midpoint && (code & 1u) == 0))
            return cast(ubyte)(sign | code);
    }
    return cast(ubyte)(sign | last_code);
}

private struct Quantized(ScalarFormat format)
{
    static if (format == ScalarFormat.binary16) private alias Storage = ushort;
    else private alias Storage = ubyte;
    private Storage payload;

    static Quantized from_code(Storage code) nothrow @nogc
    {
        Quantized result;
        static if (format == ScalarFormat.e3m2) result.payload = cast(Storage)(code & 0x3fu);
        else result.payload = code;
        return result;
    }
    Storage code() const nothrow @nogc { return payload; }
    static Quantized from_float(float value) nothrow @nogc
    {
        static if (format == ScalarFormat.binary16) return from_code(encode_half(value));
        else return from_code(encode_small!format(value));
    }
    float to_float() const nothrow @nogc
    {
        static if (format == ScalarFormat.binary16) return decode_half(payload);
        else
        {
            static if (format == ScalarFormat.e3m2) enum uint sign = 0x20;
            else enum uint sign = 0x80;
            float magnitude = decode_positive!format(cast(ubyte)(payload & (sign - 1u)));
            return (payload & sign) ? -magnitude : magnitude;
        }
    }
    Quantized opBinary(string operation)(Quantized other) const nothrow @nogc
        if (operation == "+" || operation == "-" || operation == "*" || operation == "/")
    {
        static if (format == ScalarFormat.binary16)
        {
            ushort result;
            static if (operation == "+")
                result = half_add_codes(payload, other.payload, false);
            else static if (operation == "-")
                result = half_add_codes(payload, other.payload, true);
            else static if (operation == "*")
                result = half_multiply_codes(payload, other.payload);
            else
                result = half_divide_codes(payload, other.payload);
            return from_code(result);
        }
        else
        {
            // The smaller signed formats retain their existing reference
            // policy for now: one binary32 operation followed by requantization.
            float rounded;
            static if (operation == "+") rounded = to_float() + other.to_float();
            else static if (operation == "-") rounded = to_float() - other.to_float();
            else static if (operation == "*") rounded = to_float() * other.to_float();
            else rounded = to_float() / other.to_float();
            return from_float(rounded);
        }
    }
}

// Each template instance has its own nominal type identity and exact storage.
alias Float16 = Quantized!(ScalarFormat.binary16);
alias E4M3 = Quantized!(ScalarFormat.e4m3);
alias E5M2 = Quantized!(ScalarFormat.e5m2);
alias E3M2 = Quantized!(ScalarFormat.e3m2);

/** Unsigned Ootomo-Naruse storage.
 *
 * Ordinary opBinary stays unavailable because zero, negative results and
 * out-of-range results cannot be represented. Checked +, - and * operate
 * directly on the encoded dyadic values and preserve the output on failure.
 */
struct E5M3
{
    private ubyte payload;
    static E5M3 from_code(ubyte code) nothrow @nogc
    {
        E5M3 result;
        result.payload = code;
        return result;
    }
    ubyte code() const nothrow @nogc { return payload; }
    static bool try_from_float(float value, ref E5M3 output) nothrow @nogc
    {
        uint bits = float_bits(value);
        uint exponent = (bits >> 23) & 0xffu;
        if ((bits >> 31) != 0 || exponent < 112u || exponent > 143u) return false;
        output.payload = cast(ubyte)(((bits - 0x38000000u) >> 20) & 0xffu);
        return true;
    }
    float to_float() const nothrow @nogc
    {
        return float_from_bits((cast(uint)payload << 20) + 0x38080000u);
    }

    private ulong significand() const nothrow @nogc
    {
        return 17UL + 2UL * cast(ulong)(payload & 7u);
    }
    private int exponent() const nothrow @nogc
    {
        return cast(int)(payload >> 3) - 19;
    }
    private ulong fixed_units() const nothrow @nogc
    {
        return significand() << cast(uint)(payload >> 3);
    }
    private static bool try_from_dyadic(
        ulong magnitude, int exponent, ref E5M3 output) nothrow @nogc
    {
        if (magnitude == 0) return false;
        const uint sourceTop = highest_bit(magnitude);
        const int resultExponent = cast(int)sourceTop + exponent;
        if (resultExponent < -15 || resultExponent > 16) return false;

        const uint mantissa = sourceTop >= 3
            ? cast(uint)((magnitude >> (sourceTop - 3)) & 7UL)
            : cast(uint)((magnitude << (3 - sourceTop)) & 7UL);
        output.payload = cast(ubyte)(((resultExponent + 15) << 3) | mantissa);
        return true;
    }

    static bool try_add(E5M3 left, E5M3 right, ref E5M3 output) nothrow @nogc
    {
        E5M3 candidate;
        if (!try_from_dyadic(left.fixed_units() + right.fixed_units(), -19, candidate))
            return false;
        output = candidate;
        return true;
    }
    static bool try_subtract(E5M3 left, E5M3 right, ref E5M3 output) nothrow @nogc
    {
        const ulong leftUnits = left.fixed_units();
        const ulong rightUnits = right.fixed_units();
        if (leftUnits <= rightUnits) return false;
        E5M3 candidate;
        if (!try_from_dyadic(leftUnits - rightUnits, -19, candidate))
            return false;
        output = candidate;
        return true;
    }
    static bool try_multiply(E5M3 left, E5M3 right, ref E5M3 output) nothrow @nogc
    {
        E5M3 candidate;
        if (!try_from_dyadic(
                left.significand() * right.significand(),
                left.exponent() + right.exponent(),
                candidate))
            return false;
        output = candidate;
        return true;
    }
}

static assert(Float16.sizeof == 2);
static assert(E4M3.sizeof == 1 && E5M2.sizeof == 1 && E3M2.sizeof == 1 && E5M3.sizeof == 1);
static assert(!is(E4M3 == E5M2) && !is(E5M3 == ubyte) && !is(Float16 == float));
