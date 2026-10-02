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
        // The assignment is the binary32 arithmetic boundary. Each source
        // operation requantizes; a chain may not skip intermediate rounding.
        float rounded;
        static if (operation == "+") rounded = to_float() + other.to_float();
        else static if (operation == "-") rounded = to_float() - other.to_float();
        else static if (operation == "*") rounded = to_float() * other.to_float();
        else rounded = to_float() / other.to_float();
        return from_float(rounded);
    }
}

// Each template instance has its own nominal type identity and exact storage.
alias Float16 = Quantized!(ScalarFormat.binary16);
alias E4M3 = Quantized!(ScalarFormat.e4m3);
alias E5M2 = Quantized!(ScalarFormat.e5m2);
alias E3M2 = Quantized!(ScalarFormat.e3m2);

/** Unsigned Ootomo-Naruse byte storage. There is deliberately no opBinary. */
struct UE5M3
{
    private ubyte payload;
    static UE5M3 from_code(ubyte code) nothrow @nogc
    {
        UE5M3 result;
        result.payload = code;
        return result;
    }
    ubyte code() const nothrow @nogc { return payload; }
    static bool try_from_float(float value, ref UE5M3 output) nothrow @nogc
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
}


/* Signed E5M3 ------------------------------------------------------------ */

/**
 * E5M3 is a nine-bit signed arithmetic format:
 *
 *     s eeeee mmm
 *
 * It uses an IEEE-style exponent interpretation with bias 15.  Exponent zero
 * carries signed zero/subnormals; exponent 31 carries infinity/NaN.  The
 * logical payload is nine bits, held in a 16-bit scalar container on ordinary
 * byte-addressed targets.  Dense nine-bit memory packing is a separate storage
 * representation and is not implied by this value type.
 *
 * Addition and subtraction return E5M3 and round once,
 * round-to-nearest/ties-to-even, using exact integer units of the minimum
 * subnormal. Multiplication and division are deliberately absent here:
 * callers must select a wider arithmetic format explicitly for those operations.
 */
struct E5M3
{
    private ushort payload;

    static E5M3 from_code(ushort code) nothrow @nogc
    {
        E5M3 result;
        result.payload = cast(ushort)(code & 0x01ffu);
        return result;
    }

    ushort code() const nothrow @nogc
    {
        return payload;
    }

    static E5M3 from_float(float value) nothrow @nogc
    {
        uint bits = float_bits(value);
        bool negative = (bits >> 31) != 0;
        uint exponent = (bits >> 23) & 0xffu;
        uint mantissa = bits & 0x007fffffu;

        if (exponent == 0xffu)
        {
            if (mantissa == 0)
                return signed_e5m3_infinity(negative);
            return signed_e5m3_nan();
        }

        if (exponent == 0)
        {
            if (mantissa == 0)
                return signed_e5m3_zero(negative);
            return signed_e5m3_quantize_ratio(negative, mantissa, 1u, -149);
        }

        return signed_e5m3_quantize_ratio(
            negative, 0x00800000u | mantissa, 1u, cast(int)exponent - 150);
    }

    float to_float() const nothrow @nogc
    {
        ushort raw = payload;
        uint sign = cast(uint)(raw & 0x0100u) << 23;
        uint exponent = (raw >> 3) & 0x1fu;
        uint mantissa = raw & 0x7u;

        if (exponent == 0)
        {
            if (mantissa == 0)
                return float_from_bits(sign);
            float magnitude = cast(float)mantissa * float_from_bits(0x37000000u);
            return sign ? -magnitude : magnitude;
        }

        if (exponent == 0x1fu)
            return float_from_bits(sign | 0x7f800000u | (mantissa << 20));

        return float_from_bits(sign | ((exponent + 112u) << 23) | (mantissa << 20));
    }

    E5M3 opBinary(string operation)(E5M3 other) const nothrow @nogc
        if (operation == "+" || operation == "-")
    {
        static if (operation == "+")
            return signed_e5m3_add(this, other);
        else
            return signed_e5m3_add(this, signed_e5m3_negate(other));
    }
}

private enum uint signed_e5m3_sign = 0x0100u;
private enum uint signed_e5m3_exponent_mask = 0x00f8u;
private enum uint signed_e5m3_fraction_mask = 0x0007u;
private enum uint signed_e5m3_infinity_code = 0x00f8u;
private enum uint signed_e5m3_nan_code = 0x00fcu;

private bool signed_e5m3_signbit(ushort code)
{
    return (code & signed_e5m3_sign) != 0;
}

private bool signed_e5m3_is_zero(ushort code)
{
    return (code & (signed_e5m3_exponent_mask | signed_e5m3_fraction_mask)) == 0;
}

private bool signed_e5m3_is_infinite(ushort code)
{
    return (code & signed_e5m3_exponent_mask) == signed_e5m3_exponent_mask
        && (code & signed_e5m3_fraction_mask) == 0;
}

private bool signed_e5m3_is_nan(ushort code)
{
    return (code & signed_e5m3_exponent_mask) == signed_e5m3_exponent_mask
        && (code & signed_e5m3_fraction_mask) != 0;
}

private E5M3 signed_e5m3_zero(bool negative)
{
    return E5M3.from_code(cast(ushort)(negative ? signed_e5m3_sign : 0u));
}

private E5M3 signed_e5m3_infinity(bool negative)
{
    return E5M3.from_code(cast(ushort)(
        (negative ? signed_e5m3_sign : 0u) | signed_e5m3_infinity_code));
}

private E5M3 signed_e5m3_nan()
{
    return E5M3.from_code(cast(ushort)signed_e5m3_nan_code);
}

private E5M3 signed_e5m3_negate(E5M3 value)
{
    return E5M3.from_code(cast(ushort)(value.code() ^ signed_e5m3_sign));
}

private int signed_e5m3_floor_log2(ulong value)
{
    assert(value != 0);
    int result = -1;
    while (value != 0)
    {
        value >>= 1;
        ++result;
    }
    return result;
}

private bool signed_e5m3_ratio_less_than_power(
    ulong numerator, ulong denominator, int binaryShift)
{
    if (binaryShift >= 0)
    {
        uint shift = cast(uint)binaryShift;
        assert(shift < 63 && numerator <= (ulong.max >> shift));
        return (numerator << shift) < denominator;
    }

    uint shift = cast(uint)(-binaryShift);
    assert(shift < 63 && denominator <= (ulong.max >> shift));
    return numerator < (denominator << shift);
}

private ulong signed_e5m3_round_ratio_even(
    ulong numerator, ulong denominator, int binaryShift)
{
    assert(numerator != 0 && denominator != 0);

    if (binaryShift >= 0)
    {
        uint shift = cast(uint)binaryShift;
        assert(shift < 63 && numerator <= (ulong.max >> shift));
        numerator <<= shift;
    }
    else
    {
        uint shift = cast(uint)(-binaryShift);
        assert(shift < 63 && denominator <= (ulong.max >> shift));
        denominator <<= shift;
    }

    ulong quotient = numerator / denominator;
    ulong remainder = numerator % denominator;
    if (remainder > denominator - remainder
        || (remainder == denominator - remainder && (quotient & 1u)))
        ++quotient;
    return quotient;
}

/**
 * Quantize the exact nonnegative rational
 *
 *     numerator / denominator * 2^^binaryPower
 *
 * into signed E5M3.  The caller supplies the sign separately.
 */
private E5M3 signed_e5m3_quantize_ratio(
    bool negative, ulong numerator, ulong denominator, int binaryPower)
{
    assert(denominator != 0);
    if (numerator == 0)
        return signed_e5m3_zero(negative);

    int exponent = signed_e5m3_floor_log2(numerator)
                 - signed_e5m3_floor_log2(denominator)
                 + binaryPower;

    if (signed_e5m3_ratio_less_than_power(
            numerator, denominator, binaryPower - exponent))
        --exponent;

    if (exponent > 15)
        return signed_e5m3_infinity(negative);

    // Half the minimum subnormal is 2^-18.  Anything below that rounds to zero.
    if (exponent < -18)
        return signed_e5m3_zero(negative);

    uint sign = negative ? signed_e5m3_sign : 0u;

    if (exponent >= -14)
    {
        // Round the normalized significand to four bits: implicit 1 + M3.
        ulong rounded = signed_e5m3_round_ratio_even(
            numerator, denominator, binaryPower + 3 - exponent);

        if (rounded >= 16u)
        {
            rounded = 8u;
            ++exponent;
        }

        if (exponent > 15)
            return signed_e5m3_infinity(negative);

        assert(rounded >= 8u && rounded <= 15u);
        uint storedExponent = cast(uint)(exponent + 15);
        uint fraction = cast(uint)(rounded - 8u);
        return E5M3.from_code(cast(ushort)(
            sign | (storedExponent << 3) | fraction));
    }

    // Subnormal unit is exactly 2^-17.
    ulong fraction = signed_e5m3_round_ratio_even(
        numerator, denominator, binaryPower + 17);

    if (fraction == 0)
        return signed_e5m3_zero(negative);

    // Rounding the top subnormal upward produces the minimum normal exactly.
    if (fraction >= 8u)
        return E5M3.from_code(cast(ushort)(sign | 0x0008u));

    return E5M3.from_code(cast(ushort)(sign | cast(uint)fraction));
}

private long signed_e5m3_finite_units(ushort code)
{
    uint exponent = (code >> 3) & 0x1fu;
    uint fraction = code & 0x7u;
    assert(exponent != 0x1fu);

    ulong magnitude;
    if (exponent == 0)
        magnitude = fraction;
    else
        magnitude = cast(ulong)(8u + fraction) << (exponent - 1u);

    long units = cast(long)magnitude;
    return signed_e5m3_signbit(code) ? -units : units;
}

private E5M3 signed_e5m3_add(E5M3 left, E5M3 right)
{
    ushort a = left.code();
    ushort b = right.code();

    if (signed_e5m3_is_nan(a) || signed_e5m3_is_nan(b))
        return signed_e5m3_nan();

    bool aInfinity = signed_e5m3_is_infinite(a);
    bool bInfinity = signed_e5m3_is_infinite(b);
    if (aInfinity || bInfinity)
    {
        if (aInfinity && bInfinity
            && signed_e5m3_signbit(a) != signed_e5m3_signbit(b))
            return signed_e5m3_nan();
        return aInfinity ? left : right;
    }

    bool aZero = signed_e5m3_is_zero(a);
    bool bZero = signed_e5m3_is_zero(b);
    if (aZero && bZero)
        return signed_e5m3_zero(
            signed_e5m3_signbit(a) && signed_e5m3_signbit(b));
    if (aZero)
        return right;
    if (bZero)
        return left;

    long sum = signed_e5m3_finite_units(a) + signed_e5m3_finite_units(b);
    if (sum == 0)
        return signed_e5m3_zero(false);

    bool negative = sum < 0;
    ulong magnitude = cast(ulong)(negative ? -sum : sum);
    return signed_e5m3_quantize_ratio(negative, magnitude, 1u, -17);
}

static assert(Float16.sizeof == 2);
static assert(E4M3.sizeof == 1 && E5M2.sizeof == 1 && E3M2.sizeof == 1 && UE5M3.sizeof == 1);
static assert(E5M3.sizeof == 2, "nine-bit E5M3 uses a 16-bit scalar container");
static assert(!is(E4M3 == E5M2) && !is(UE5M3 == ubyte) && !is(Float16 == float));
static assert(!is(E5M3 == UE5M3) && !is(E5M3 == ushort));
