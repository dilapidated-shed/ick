module acceptance;
import icky.imprecise : E5M3, Float16;
import icky.experimental.e5m3_left;
extern(C) int puts(const(char)*) nothrow @nogc;
nothrow @nogc:

private union FloatBits { float value; uint bits; }
uint bits(float value) { FloatBits view; view.value = value; return view.bits; }
float value(uint raw) { FloatBits view; view.bits = raw; return view.value; }

void canonical(LeftE5M3 result)
{
    assert((result.storage() & 0x007fu) == 0);
}

extern(C) int main()
{
    foreach (uint raw; 0 .. 65536u)
    {
        auto before = LeftE5M3.from_code(0x123);
        bool accepted = LeftE5M3.try_from_storage(cast(ushort)raw, before);
        assert(accepted == ((raw & 0x7fu) == 0));
        if (accepted) assert(before.storage() == raw);
        else assert(before.code() == 0x123);

        auto half = Float16.from_code(cast(ushort)raw);
        auto actual = LeftE5M3.narrow(half);
        auto expected = E5M3.from_float(half.to_float());
        canonical(actual);
        assert(actual.code() == expected.code());
        assert(narrow_half_to_right(half).code() == expected.code());
    }
    puts("PASS: all 65536 FP16 inputs and all 65536 storage validation inputs");

    LeftE5M3[512] stored;
    foreach (uint a; 0 .. 512u)
    {
        auto right = E5M3.from_code(cast(ushort)a);
        auto left = LeftE5M3.from_code(cast(ushort)a);
        canonical(left);
        stored[a] = left;
        assert((cast(const(ushort)*)stored.ptr)[a] == a << 7);
        assert(stored[a].code() == a);
        assert(left.code() == right.code());
        assert(bits(left.widen().to_float()) == bits(right.to_float()));
        assert(left.widen().code() == a << 7);
        assert(left.negate().code() == (a ^ 0x100u));
        assert(left.signbit() == ((a & 0x100u) != 0));
        assert(LeftE5M3.narrow(left.widen()).code() ==
               E5M3.from_float(right.to_float()).code());

        foreach (uint b; 0 .. 512u)
        {
            auto r = E5M3.from_code(cast(ushort)b);
            auto l = LeftE5M3.from_code(cast(ushort)b);
            auto sum = left + l;
            auto difference = left - l;
            canonical(sum); canonical(difference);
            assert(sum.code() == (right + r).code());
            assert(difference.code() == (right - r).code());

            auto product = multiply_via_explicit_half(left, l);
            auto referenceProduct = E5M3.from_float(
                (Float16.from_code(cast(ushort)(a << 7)) *
                 Float16.from_code(cast(ushort)(b << 7))).to_float());
            canonical(product);
            assert(product.code() == referenceProduct.code());

            float av = right.to_float(), bv = r.to_float();
            assert(left.equal(l) == (av == bv));
            assert(left.less(l) == (av < bv));
            assert(l.less(left) == (av > bv));
            assert((left.less(l) || left.equal(l)) == (av <= bv));
            assert((l.less(left) || left.equal(l)) == (av >= bv));
            assert(!left.equal(l) == (av != bv));
        }
    }
    puts("PASS: all 512 values; all 262144 pairs for add/sub/explicit-half-multiply and six comparisons");

    // Independent midpoint oracle. Every finite positive rounding boundary,
    // its binary32 predecessor, exact tie, and successor, for both signs.
    foreach (uint lower; 0 .. 248u)
    {
        float lo = E5M3.from_code(cast(ushort)lower).to_float();
        // The conceptual successor to 61440 is 65536, rounded to infinity.
        float hi = lower == 247u ? 65536.0f :
            E5M3.from_code(cast(ushort)(lower + 1u)).to_float();
        uint midpoint = bits(lo + (hi - lo) * 0.5f);
        foreach (uint sign; [0u, 0x80000000u])
        {
            foreach (uint side; 0 .. 3u)
            {
                uint input = midpoint + side - 1u;
                uint selected = side == 0 ? lower : side == 2 ? lower + 1u :
                    lower + (lower & 1u);
                ushort expected = cast(ushort)(selected | (sign >> 23));
                assert(E5M3.from_float(value(input | sign)).code() == expected);
                auto actual = LeftE5M3.from_code(
                    E5M3.from_float(value(input | sign)).code());
                canonical(actual);
                assert(actual.code() == expected);
            }
        }
    }
    puts("PASS: 1488 binary32 rounding-boundary neighbours and ties; NaN normalization stays specified");
    return 0;
}
