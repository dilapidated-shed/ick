/** Sun F03: alternate storage only; icky.imprecise owns numerical semantics. */
module icky.experimental.e5m3_left;

import icky.imprecise : E5M3, Float16;
nothrow @nogc:

struct LeftE5M3
{
    nothrow @nogc:
    private ushort payload;

    static LeftE5M3 from_code(ushort code)
    {
        LeftE5M3 result;
        result.payload = cast(ushort)((code & 0x01ffu) << 7);
        return result;
    }

    // Reject malformed persistent storage; never repair it silently.
    static bool try_from_storage(ushort storage, ref LeftE5M3 output)
    {
        if (storage & 0x007fu) return false;
        output.payload = storage;
        return true;
    }

    ushort storage() const { return payload; }
    ushort code() const { return cast(ushort)(payload >> 7); }
    E5M3 reference() const { return E5M3.from_code(code()); }

    Float16 widen() const { return Float16.from_code(payload); }

    static LeftE5M3 narrow(Float16 value)
    {
        uint raw = value.code();
        uint magnitude = raw & 0x7fffu;
        // Match the established E5M3 conversion: every NaN becomes +0xfc.
        if (magnitude > 0x7c00u) return from_code(0x00fc);
        if (magnitude == 0x7c00u)
        {
            LeftE5M3 result;
            result.payload = cast(ushort)(raw);
            return result;
        }
        // RNE in the common binary16 exponent lattice, including subnormal,
        // normal carry, and the 63488 overflow tie. Sign stays separate.
        uint remainder = magnitude & 0x007fu;
        uint rounded = magnitude & 0xff80u;
        if (remainder > 64u || (remainder == 64u && (rounded & 0x0080u)))
            rounded += 0x0080u;
        LeftE5M3 result;
        result.payload = cast(ushort)((raw & 0x8000u) | rounded);
        return result;
    }

    LeftE5M3 opBinary(string operation)(LeftE5M3 other) const
        if (operation == "+" || operation == "-")
    {
        // Preserve direct E5M3 arithmetic, including its special-value rules.
        static if (operation == "+")
            return from_code((reference() + other.reference()).code());
        else
            return from_code((reference() - other.reference()).code());
    }

    LeftE5M3 negate() const
    {
        LeftE5M3 result;
        result.payload = cast(ushort)(payload ^ 0x8000u);
        return result;
    }

    bool is_nan() const { return (payload & 0x7fffu) > 0x7c00u; }
    bool is_zero() const { return (payload & 0x7fffu) == 0; }
    bool signbit() const { return (payload & 0x8000u) != 0; }

    bool equal(LeftE5M3 other) const
    {
        if (is_nan() || other.is_nan()) return false;
        return payload == other.payload || (is_zero() && other.is_zero());
    }

    bool less(LeftE5M3 other) const
    {
        if (is_nan() || other.is_nan() || (is_zero() && other.is_zero()))
            return false;
        if (signbit() != other.signbit()) return signbit();
        return signbit() ? payload > other.payload : payload < other.payload;
    }
}

// Explicit experiment pipeline, not an E5M3 multiplication operator.
// Float16 first rounds the product under its existing contract; narrowing
// then rounds to E5M3. Do not replace this with a single-round exact product.
LeftE5M3 multiply_via_explicit_half(LeftE5M3 left, LeftE5M3 right)
{
    return LeftE5M3.narrow(left.widen() * right.widen());
}

// Matched-algorithm right-layout control: avoids attributing a new half-bit
// quantizer's speed to the storage representation itself.
E5M3 narrow_half_to_right(Float16 value)
{
    return E5M3.from_code(LeftE5M3.narrow(value).code());
}

static assert(LeftE5M3.sizeof == E5M3.sizeof && LeftE5M3.sizeof == 2);
static assert(!__traits(compiles, LeftE5M3.init * LeftE5M3.init));
