module representation_acceptance;

import icky.imprecise;
import icky.circle;
import icky.packed;
import icky.packed_memory;

nothrow @nogc:
extern(C) uint oracle_decode(uint format, uint code);
extern(C) uint oracle_encode(uint format, uint bits);
extern(C) uint oracle_operation(uint format, uint operation, uint left, uint right);
extern(C) uint oracle_signed_e5m3_operation(uint operation, uint left, uint right);
extern(C) uint oracle_signed_e5m3_compare(uint predicate, uint left, uint right);
extern(C) uint oracle_float16_chain(uint firstOperation, uint secondOperation,
                                    uint left, uint middle, uint right);
extern(C) uint oracle_packed_operation(uint left_format, uint right_format,
                                      uint operation, uint left, uint right);
extern(C) int oracle_circle(uint operation, int first, int second);
extern(C) int puts(const char* text);

private union FloatBits { float value; uint bits; }
private uint bits_of(float value)
{
    FloatBits view;
    view.value = value;
    return view.bits;
}
private float value_of(uint bits)
{
    FloatBits view;
    view.bits = bits;
    return view.value;
}
private bool nan_bits(uint bits)
{ return (bits & 0x7fffffffu) > 0x7f800000u; }

static assert(!__traits(compiles, UE5M3.init + UE5M3.init));
static assert(__traits(compiles, E5M3.init + E5M3.init));
static assert(__traits(compiles, E5M3.init - E5M3.init));
static assert(__traits(compiles, -E5M3.init));
static assert(!__traits(compiles, E5M3.init * E5M3.init));
static assert(!__traits(compiles, E5M3.init / E5M3.init));
static assert(E5M3.sizeof == 2);
static assert(!__traits(compiles, E4M3.init + E5M2.init));
static assert(!__traits(compiles, Circle96.init + Circle96.init));
static assert(!__traits(compiles, rotate(Rotation192.init, Circle96.init)));
static assert(!__traits(compiles, Circle96.init.payload));
static assert(!__traits(compiles, Circle96(255)));
static assert(!__traits(compiles, UE5M3.init.payload));

void check_encoding(T, uint format)(uint bits)
{
    auto got = T.from_float(value_of(bits));
    assert(got.code() == oracle_encode(format, bits));
}

void check_operations(T, uint format)(uint left, uint right)
{
    alias Code = typeof(T.init.code());
    auto a = T.from_code(cast(Code)left);
    auto b = T.from_code(cast(Code)right);
    // NaN propagation signs/payloads are not part of the representation ABI.
    if ((bits_of(a.to_float()) & 0x7fffffffu) >= 0x7f800000u ||
        (bits_of(b.to_float()) & 0x7fffffffu) >= 0x7f800000u) return;
    T[4] results = [a + b, a - b, a * b, a / b];
    foreach (uint operation; 0 .. 4)
    {
        uint expected = oracle_operation(format, operation, left, right);
        uint got = results[operation].code();
        if (nan_bits(oracle_decode(format, expected)))
            assert(nan_bits(bits_of(results[operation].to_float())));
        else assert(got == expected);
    }
}

void check_format(T, uint format, uint count)()
{
    alias Code = typeof(T.init.code());
    foreach (uint code; 0 .. count)
    {
        auto value = T.from_code(cast(Code)code);
        uint decoded = bits_of(value.to_float());
        assert(decoded == oracle_decode(format, code));
        check_encoding!(T, format)(decoded);
    }
    uint state = 0x4d595df4u;
    foreach (uint sample; 0 .. 16384)
    {
        state = state * 1664525u + 1013904223u;
        check_encoding!(T, format)(state);
    }
    foreach (uint bits; [0u, 0x80000000u, 1u, 0x007fffffu, 0x00800000u,
                        0x7f7fffffu, 0xff7fffffu, 0x7f800000u, 0xff800000u,
                        0x7fc00000u, 0xffc00000u, 0x7f800001u])
        check_encoding!(T, format)(bits);
    foreach (uint left; 0 .. (count < 256 ? count : 256))
    foreach (uint right; 0 .. (count < 256 ? count : 256))
        check_operations!(T, format)(left, right);
    static if (format == 0)
    {
        foreach (uint left; [0u, 0x8000u, 1u, 0x3c00u, 0x4000u, 0x7bffu,
                            0x0400u, 0x3555u, 0x8001u, 0xfbffu])
        foreach (uint right; [0u, 0x8000u, 1u, 0x3c00u, 0x4000u, 0x7bffu,
                             0x0400u, 0x3555u, 0x8001u, 0xfbffu])
            check_operations!(T, format)(left, right);
    }
}

void check_midpoints(T, uint format, uint last_code)()
{
    alias Code = typeof(T.init.code());
    foreach (uint code; 0 .. last_code)
    {
        float lower = T.from_code(cast(Code)code).to_float();
        float upper = T.from_code(cast(Code)(code + 1)).to_float();
        uint middle = bits_of(lower + (upper - lower) * 0.5f);
        uint[3] candidates = [middle - 1u, middle, middle + 1u];
        foreach (uint candidate; candidates)
        {
            check_encoding!(T, format)(candidate);
            check_encoding!(T, format)(candidate | 0x80000000u);
        }
    }
}


void check_signed_e5m3()
{
    enum ushort sign = 0x100u;
    enum ushort positiveInfinity = 0x0f8u;
    enum ushort negativeInfinity = 0x1f8u;
    enum ushort canonicalNaN = 0x0fcu;

    // Every nine-bit payload decodes.  Every non-NaN payload round-trips
    // through binary32 exactly because binary32 is only a conversion surface,
    // not the arithmetic carrier.
    foreach (uint code; 0 .. 512)
    {
        auto value = E5M3.from_code(cast(ushort)code);
        assert(value.code() == code);
        auto decoded = value.to_float();
        uint exponent = (code >> 3) & 0x1fu;
        uint fraction = code & 0x7u;
        assert((-value).code() == (
            exponent == 0x1fu && fraction != 0 ? canonicalNaN : (code ^ sign)));
        if (exponent == 0x1fu && fraction != 0)
        {
            assert(nan_bits(bits_of(decoded)));
            assert(E5M3.from_float(decoded).code() == canonicalNaN);
        }
        else
            assert(E5M3.from_float(decoded).code() == code);
    }

    assert(E5M3.from_code(0x3ffu).code() == 0x1ffu);

    // Exhaust all signed payload pairs against an independently written C
    // oracle. It uses exact integer units and midpoint binary search, not
    // binary32 arithmetic or the D ratio quantizer being tested here.
    foreach (uint leftCode; 0 .. 512)
    foreach (uint rightCode; 0 .. 512)
    {
        auto left = E5M3.from_code(cast(ushort)leftCode);
        auto right = E5M3.from_code(cast(ushort)rightCode);

        assert((left + right).code() ==
               oracle_signed_e5m3_operation(0, leftCode, rightCode));
        assert((left - right).code() ==
               oracle_signed_e5m3_operation(1, leftCode, rightCode));
        assert(left.equal(right) ==
               (oracle_signed_e5m3_compare(0, leftCode, rightCode) != 0));
        assert(left.less(right) ==
               (oracle_signed_e5m3_compare(1, leftCode, rightCode) != 0));
    }

    // Layout and landmarks: s eeeee mmm, bias 15.
    assert(bits_of(E5M3.from_code(0x000u).to_float()) == 0x00000000u);
    assert(bits_of(E5M3.from_code(sign).to_float()) == 0x80000000u);
    assert(bits_of(E5M3.from_code(0x001u).to_float()) == 0x37000000u); // 2^-17
    assert(bits_of(E5M3.from_code(0x008u).to_float()) == 0x38800000u); // 2^-14
    assert(bits_of(E5M3.from_code(0x078u).to_float()) == bits_of(1.0f));
    assert(bits_of(E5M3.from_code(0x178u).to_float()) == bits_of(-1.0f));
    assert(bits_of(E5M3.from_code(0x0f7u).to_float()) == bits_of(61440.0f));
    assert(bits_of(E5M3.from_code(positiveInfinity).to_float()) == 0x7f800000u);
    assert(bits_of(E5M3.from_code(negativeInfinity).to_float()) == 0xff800000u);
    assert(nan_bits(bits_of(E5M3.from_code(canonicalNaN).to_float())));

    // Round-to-nearest, ties-to-even at ordinary, underflow and overflow edges.
    assert(E5M3.from_float(1.0625f).code() == 0x078u);
    assert(E5M3.from_float(1.1875f).code() == 0x07au);
    assert(E5M3.from_float(value_of(0x36800000u)).code() == 0x000u); // 2^-18 tie -> +0
    assert(E5M3.from_float(value_of(0xb6800000u)).code() == sign);   // -2^-18 tie -> -0
    assert(E5M3.from_float(63487.0f).code() == 0x0f7u);
    assert(E5M3.from_float(63488.0f).code() == positiveInfinity);

    auto positiveZero = E5M3.from_code(0x000u);
    auto negativeZero = E5M3.from_code(sign);
    auto one = E5M3.from_code(0x078u);
    auto negativeOne = E5M3.from_code(0x178u);
    auto two = E5M3.from_code(0x080u);
    auto infinity = E5M3.from_code(positiveInfinity);
    auto negativeInfinityValue = E5M3.from_code(negativeInfinity);

    // Addition/subtraction stay in E5M3. Exact cancellation is +0.
    assert((one + one).code() == two.code());
    assert((one - two).code() == negativeOne.code());
    assert((one - one).code() == positiveZero.code());
    assert((negativeZero + negativeZero).code() == negativeZero.code());
    assert((positiveZero + negativeZero).code() == positiveZero.code());
    assert((negativeZero - positiveZero).code() == negativeZero.code());
    assert((-negativeZero).code() == positiveZero.code());
    assert((-one).code() == negativeOne.code());
    assert((-infinity).code() == negativeInfinityValue.code());

    // Numerical comparisons have unordered NaNs and equal signed zeros;
    // no total-order or operator overload is invented for NaNs.
    auto nan = E5M3.from_code(canonicalNaN);
    assert(!nan.equal(nan) && !nan.less(nan));
    assert(negativeZero.equal(positiveZero));
    assert(!negativeZero.less(positiveZero));
    assert(!positiveZero.less(negativeZero));
    assert(negativeOne.less(negativeZero));
    assert(negativeZero.less(one));
    assert((-nan).code() == canonicalNaN);

    // Multiplication/division are the explicit promotion boundary, not E5M3
    // operators. Addition still has explicit special-value behavior.
    assert(nan_bits(bits_of((infinity + negativeInfinityValue).to_float())));

    puts("PASS: signed nine-bit E5M3 add/sub/negate and unordered comparisons against exact C oracle");
}

void check_storage()
{
    foreach (uint code; 0 .. 256)
    {
        auto value = UE5M3.from_code(cast(ubyte)code);
        assert(bits_of(value.to_float()) == oracle_decode(4, code));
        UE5M3 result;
        assert(UE5M3.try_from_float(value.to_float(), result));
        assert(result.code() == code);
    }
    uint state = 0x735a2d97u;
    foreach (uint sample; 0 .. 16384)
    {
        state = state * 1664525u + 1013904223u;
        auto output = UE5M3.from_code(73);
        uint expected = oracle_encode(4, state);
        bool accepted = UE5M3.try_from_float(value_of(state), output);
        assert(accepted == (expected != 0x10000u));
        assert(output.code() == (accepted ? expected : 73));
    }
    foreach (uint bits; [0u, 0x80000000u, 1u, 0x37ffffffu, 0x38000000u,
                        0x47ffffffu, 0x48000000u, 0xbf800000u, 0x7f800000u,
                        0xff800000u, 0x7fc00000u])
    {
        auto output = UE5M3.from_code(73);
        uint expected = oracle_encode(4, bits);
        bool accepted = UE5M3.try_from_float(value_of(bits), output);
        assert(accepted == (expected != 0x10000u));
        assert(output.code() == (accepted ? expected : 73));
    }
}

void check_float16_rounding_chain()
{
    auto left = Float16.from_float(1.0f);
    auto middle = Float16.from_float(0.00048828125f);
    auto right = Float16.from_float(1.5f);
    auto roundedIntermediate = left + middle;
    auto got = roundedIntermediate * right;
    auto expected = oracle_float16_chain(0, 2, left.code(), middle.code(), right.code());
    auto withoutIntermediateRounding = Float16.from_float(
        (left.to_float() + middle.to_float()) * right.to_float());
    assert(roundedIntermediate.code() == left.code());
    assert(got.code() == expected);
    assert(got.code() != withoutIntermediateRounding.code());
}

void check_packed_operation(string operation, Left, Right)(
    Left[] left, Right[] right, uint leftFormat, uint rightFormat)
{
    foreach (uint leftIndex; 0 .. 256)
    foreach (uint rightIndex; 0 .. 256)
    {
        const leftCode = left[leftIndex].code();
        const rightCode = right[rightIndex].code();
        auto result = compute_at!(Float16, operation)(
            left[], leftIndex, right[], rightIndex);
        const expected = oracle_packed_operation(
            leftFormat, rightFormat,
            operation == "+" ? 0 : operation == "-" ? 1 : operation == "*" ? 2 : 3,
            leftCode, rightCode);
        assert(result.code() == expected);
    }
}

void check_packed_operation_pairs(Left, Right)(uint leftFormat, uint rightFormat)
{
    Left[256] left;
    Right[256] right;
    foreach (uint code; 0 .. 256)
    {
        left[code] = Left.from_code(cast(typeof(left[code].code()))code);
        right[code] = Right.from_code(cast(typeof(right[code].code()))code);
    }
    check_packed_operation!("+")(left[], right[], leftFormat, rightFormat);
    check_packed_operation!("-")(left[], right[], leftFormat, rightFormat);
    check_packed_operation!("*")(left[], right[], leftFormat, rightFormat);
    check_packed_operation!("/")(left[], right[], leftFormat, rightFormat);
}

void check_packed_memory_surface()
{
    static assert(UE5M3.sizeof == 1 && E3M2.sizeof == 1 && Float16.sizeof == 2);
    UE5M3[2] adjacent_e5 = [UE5M3.from_code(7), UE5M3.from_code(9)];
    E3M2[2] adjacent_e3 = [E3M2.from_code(7), E3M2.from_code(9)];
    assert((&adjacent_e5[1] - &adjacent_e5[0]) == 1);
    assert((&adjacent_e3[1] - &adjacent_e3[0]) == 1);

    UE5M3[256] e5;
    E3M2[256] e3;
    foreach (uint code; 0 .. 256)
    {
        e5[code] = UE5M3.from_code(cast(ubyte)code);
        e3[code] = E3M2.from_code(cast(ubyte)code);
        assert(e3[code].code() == (code & 0x3fu));

        auto widened = Float16.from_float(e5[code].to_float());
        if (code < 248)
            assert((widened.code() & 0x7c00u) != 0x7c00u);
        else
            assert(widened.code() == 0x7c00u);
    }

    // Every UE5M3/UE5M3 operation pair, including mixed signed-zero, subnormal,
    // infinity and NaN cases after the required Float16 operand conversion.
    check_packed_operation_pairs!(UE5M3, UE5M3)(4, 4);
    check_packed_operation_pairs!(UE5M3, E3M2)(4, 3);
    check_packed_operation_pairs!(E3M2, UE5M3)(3, 4);
    check_packed_operation_pairs!(E3M2, E3M2)(3, 3);

    UE5M3[1] one_e5 = [UE5M3.from_code(120)];
    E3M2[1] one_e3 = [E3M2.from_code(12)];
    auto one_result = compute_at!(Float16, "*")(
        one_e5[], 0, one_e3[], 0);
    assert(one_result.code() ==
        oracle_packed_operation(4, 3, 2, one_e5[0].code(), one_e3[0].code()));

    auto offset_left = e5[19 .. 22];
    auto offset_right = e3[33 .. 36];
    auto offset_result = compute_at!(Float16, "-")(
        offset_left, 2, offset_right, 2);
    assert(offset_result.code() == oracle_packed_operation(
        4, 3, 1, e5[21].code(), e3[35].code()));

    auto exact_alias = compute_at!(Float16, "+")(one_e5[], 0, one_e5[], 0);
    assert(exact_alias.code() == oracle_packed_operation(
        4, 4, 0, one_e5[0].code(), one_e5[0].code()));

    // The same positive storage can select signed E5M3 arithmetic explicitly.
    // Subtraction does not widen to Float16: a negative result remains E5M3.
    UE5M3[1] signed_left;
    UE5M3[1] signed_right;
    assert(UE5M3.try_from_float(1.0f, signed_left[0]));
    assert(UE5M3.try_from_float(2.0f, signed_right[0]));
    auto signed_difference = compute_at!(E5M3, "-")(
        signed_left[], 0, signed_right[], 0);
    assert(signed_difference.code() == 0x178u); // -1

    // Storing a negative signed result back into positive-only UE5M3 is an
    // explicit domain failure and preserves the destination.
    UE5M3[1] signed_destination = [UE5M3.from_code(73)];
    assert(!try_store_at(signed_destination[], 0, signed_difference));
    assert(signed_destination[0].code() == 73);

    auto signed_sum = compute_at!(E5M3, "+")(
        signed_left[], 0, signed_right[], 0);
    assert(bits_of(signed_sum.to_float()) == bits_of(3.0f));
    assert(try_store_at(signed_destination[], 0, signed_sum));
    UE5M3 expected_signed_store;
    assert(UE5M3.try_from_float(3.0f, expected_signed_store));
    assert(signed_destination[0].code() == expected_signed_store.code());

    // A function pointer keeps the same direct E5M3 scalar fallback.
    auto signed_subtract = &compute_at!(E5M3, "-", UE5M3, UE5M3);
    assert(signed_subtract(signed_left[], 0, signed_right[], 0).code() == 0x178u);

    // One coordinate, odd length, nonzero offset, final valid index and the
    // first and very large invalid indices all use the checked store surface.
    UE5M3[5] sentinels = [UE5M3.from_code(17), UE5M3.from_code(31),
                         UE5M3.from_code(47), UE5M3.from_code(63),
                         UE5M3.from_code(79)];
    auto odd = sentinels[1 .. 4];
    assert(try_store_at(odd, 2, Float16.from_float(2.0f)));
    assert(!try_store_at(odd, 3, Float16.from_float(2.0f)));
    assert(!try_store_at(odd, size_t.max, Float16.from_float(2.0f)));
    assert(sentinels[0].code() == 17 && sentinels[4].code() == 79);

    UE5M3[1] one;
    assert(try_store_at(one[], 0, Float16.from_float(1.0f)));
    UE5M3[0] empty;
    assert(!try_store_at(empty[], 0, Float16.from_float(1.0f)));

    // UE5M3's partial encoder preserves the destination on every rejected
    // result; E3M2 retains its total saturation and NaN mapping.
    auto saved = one[0].code();
    assert(!try_store_at(one[], 0, Float16.from_float(-1.0f)));
    assert(one[0].code() == saved);
    assert(!try_store_at(one[], 1, Float16.from_float(1.0f)));
    E3M2[1] e3_destination = [E3M2.from_code(17)];
    auto saturated = Float16.from_float(1000000.0f);
    assert(try_store_at(e3_destination[], 0, saturated));
    assert(e3_destination[0].code() == oracle_encode(3, bits_of(saturated.to_float())));
    auto nan = Float16.from_float(value_of(0x7fc00000u));
    assert(try_store_at(e3_destination[], 0, nan));
    assert(e3_destination[0].code() == 0);

    // Exact aliasing and overlap remain ordinary sequenced D memory effects;
    // no disjointness is inferred from different slice expressions.
    UE5M3[4] overlap = [UE5M3.from_code(1), UE5M3.from_code(2),
                       UE5M3.from_code(3), UE5M3.from_code(4)];
    auto first = overlap[0 .. 3];
    auto second = overlap[1 .. 4];
    auto before = compute_at!(Float16, "+")(first, 1, second, 1);
    const expectedBefore = oracle_packed_operation(4, 4, 0,
                                                   overlap[1].code(), overlap[2].code());
    assert(before.code() == expectedBefore);
    assert(try_store_at(second, 0, Float16.from_float(3.0f)));
    assert(overlap[1].code() == oracle_encode(4,
        bits_of(Float16.from_float(3.0f).to_float())));
    assert(overlap[0].code() == 1 && overlap[3].code() == 4);

    // A function address remains an ordinary callable D function.
    auto multiply = &compute_at!(Float16, "*", UE5M3, UE5M3);
    assert(multiply(first, 0, second, 0).code() ==
           oracle_packed_operation(4, 4, 2, overlap[0].code(), overlap[1].code()));
    auto store = &try_store_at!(UE5M3, Float16);
    UE5M3[1] address_destination = [UE5M3.from_code(81)];
    assert(store(address_destination[], 0, Float16.from_float(1.0f)));
    assert(address_destination[0].code() == oracle_encode(4, bits_of(1.0f)));
}

void check_packed_memory()
{
    static assert(PackedValue!(UE5M3, Float16).sizeof == UE5M3.sizeof);
    static assert(PackedView!(UE5M3, Float16, 8, 7).known_alignment == 8);
    static assert(PackedView!(UE5M3, Float16, 8, 7).alias_set == 7);

    align(8) struct ByteBuffer { ubyte[512] data; }
    ByteBuffer buffer;
    foreach (size_t code; 0 .. 256)
        buffer.data[code * 2] = cast(ubyte)code;
    assert((cast(size_t)buffer.data.ptr & 7) == 0);
    auto view = PackedView!(UE5M3, Float16, 8, 7)(
        buffer.data.ptr, buffer.data.length, 2);
    foreach (size_t code; 0 .. 256)
    {
        PackedValue!(UE5M3, Float16) stored;
        assert(view.try_load(code, stored));
        assert(stored.stored.code() == code);
        auto widened = stored.decode();
        auto expectedWidened = Float16.from_float(value_of(oracle_decode(4, cast(uint)code)));
        assert(bits_of(widened.to_float()) == bits_of(expectedWidened.to_float()));

        // Some finite UE5M3 extremes overflow the existing Float16 semantics.
        // Narrowing then follows UE5M3's existing partial input-domain rule.
        const expectedCode = oracle_encode(4, bits_of(widened.to_float()));
        UE5M3 encoded = UE5M3.from_code(91);
        const accepted = PackedValue!(UE5M3, Float16).try_encode(widened, encoded);
        assert(accepted == (expectedCode != 0x10000u));
        if (accepted) assert(encoded.code() == expectedCode);
        else assert(encoded.code() == 91);

        assert(view.try_store(code, widened) == accepted);
        assert(buffer.data[code * 2] == (accepted ? expectedCode : code));
    }

    // Failed bounds checks and failed UE5M3-domain encodes preserve storage.
    PackedValue!(UE5M3, Float16) unchanged = { UE5M3.from_code(91) };
    assert(!view.try_load(256, unchanged));
    assert(unchanged.stored.code() == 91);
    assert(!view.try_store(256, Float16.from_float(1.0f)));
    assert(!view.try_store(0, Float16.from_float(-1.0f)));
    assert(!view.try_store(0, Float16.from_float(0.0f)));
    assert(!view.try_store(0, Float16.from_float(-0.0f)));
    assert(!view.try_store(0, Float16.from_float(1.0e-7f)));
    assert(!view.try_store(0, Float16.from_float(value_of(0x7f800000u))));
    assert(!view.try_store(0, Float16.from_float(value_of(0x7fc00000u))));
    assert(buffer.data[0] == 0);
    // Ordinary unit-stride access uses the same scalar operation at each index.
    auto unit = PackedView!(UE5M3, Float16, 8, 0)(buffer.data.ptr, buffer.data.length, 1);
    auto arithmetic = Float16.from_float(2.0f) * Float16.from_float(1.5f);
    assert(unit.try_store(5, arithmetic));
    assert(buffer.data[5] == oracle_encode(4, bits_of(arithmetic.to_float())));
    PackedValue!(UE5M3, Float16) product;
    assert(unit.try_load(5, product));
    assert(product.stored.code() == buffer.data[5]);
    assert(bits_of(product.decode().to_float()) == oracle_decode(4, buffer.data[5]));
    assert(oracle_decode(4, 0) != 0x00000000u); // code zero is an unsigned midpoint, not IEEE zero
    assert(!unit.try_load(size_t.max, product));

    auto loadFacts = view.load_operation(3);
    assert(loadFacts.action == PackedAction.load &&
           loadFacts.effect == PackedEffect.read &&
           loadFacts.ordering == PackedOrdering.ordinary &&
           loadFacts.byteStride == 2 && loadFacts.knownAlignment == 8 &&
           loadFacts.aliasSet == 7 && loadFacts.elementIndex == 3);
    auto storeFacts = view.store_operation(3);
    assert(storeFacts.action == PackedAction.store &&
           storeFacts.effect == PackedEffect.write &&
           storeFacts.byteStride == 2 && storeFacts.aliasSet == 7);

    puts("PASS: packed scalar load, local F16 widening, arithmetic, narrowing and store");
    puts("PASS: all 256 UE5M3 encodings, non-unit stride, bounds, layout and memory facts");
}

void check_grid(uint positions)()
{
    alias Point = Circle!positions;
    alias Turn = Rotation!positions;
    alias Mirror = Reflection!positions;
    alias Offset = Tangent!positions;
    auto saved = Point.from_ticks(17);
    assert(!Point.try_from_code(positions, saved) && saved.code() == 17);
    auto saved_turn = Turn.from_ticks(17);
    assert(!Turn.try_from_code(positions, saved_turn) && saved_turn.code() == 17);
    assert(Turn.try_from_code(positions - 1, saved_turn) && saved_turn.code() == positions - 1);
    auto saved_mirror = Mirror.from_ticks(17);
    assert(!Mirror.try_from_code(positions, saved_mirror) && saved_mirror.code() == 17);
    assert(Mirror.try_from_code(positions - 1, saved_mirror) && saved_mirror.code() == positions - 1);
    assert(Point.from_ticks(-1).code() == positions - 1);
    assert(Point.from_ticks(cast(long)positions * 17 + 3).code() == 3);
    Offset offset;
    assert(!Offset.try_from_ticks(cast(int)(positions / 2), offset));
    assert(Offset.try_from_ticks(-cast(int)(positions / 2), offset));
    foreach (uint a; 0 .. positions)
    {
        auto point = Point.from_ticks(a);
        assert(point.third_sector() * (positions / 3) + point.position_within_third() == a);
        assert(local_displacement(rotate(Turn.from_ticks(positions / 2), point), point).ticks()
               == -cast(int)(positions / 2));
        foreach (uint b; 0 .. positions)
        {
            auto turn = Turn.from_ticks(b);
            auto mirror = Mirror.from_ticks(b);
            assert(rotate(inverse_rotation(turn), rotate(turn, point)).code() == a);
            assert(reflect(mirror, reflect(mirror, point)).code() == a);
            auto destination = Point.from_ticks(b);
            auto displacement = local_displacement(destination, point);
            assert(displace(point, displacement).code() == b);
            assert(displacement.ticks() >= -cast(int)(positions / 2));
            assert(displacement.ticks() < cast(int)(positions / 2));
            static if (positions == 96)
            {
                assert(rotate(turn, point).code() == oracle_circle(0, b, a));
                assert(reflect(mirror, point).code() == oracle_circle(1, b, a));
                assert(displacement.ticks() == oracle_circle(2, b, a));
                assert(compose_rotations(Turn.from_ticks(a), turn).code() == oracle_circle(3, a, b));
                assert(inverse_rotation(turn).code() == oracle_circle(4, b, 0));
            }
        }
    }
}

extern(C) int main()
{
    check_packed_memory_surface();
    check_float16_rounding_chain();
    check_packed_memory();
    check_format!(Float16, 0, 65536)();
    check_format!(E4M3, 1, 256)();
    check_format!(E5M2, 2, 256)();
    check_format!(E3M2, 3, 256)();
    check_midpoints!(Float16, 0, 0x7bff)();
    check_midpoints!(E4M3, 1, 0x7e)();
    check_midpoints!(E5M2, 2, 0x7b)();
    check_midpoints!(E3M2, 3, 0x1f)();
    foreach (uint bits; [0x477fefffu, 0x477ff000u, 0x477ff001u])
        check_encoding!(Float16, 0)(bits);
    check_storage();
    check_signed_e5m3();
    puts("PASS: all scalar payloads, boundary quantization and arithmetic against the C oracle");
    check_grid!96();
    check_grid!192();
    check_grid!240();
    check_grid!360();
    check_grid!720();
    puts("PASS: finite-circle laws, canonical codes and the exact Circle96 C oracle");
    puts("PASS: forbidden UE5M3 arithmetic and mixed geometric/scalar categories rejected");
    return 0;
}
