module representation_acceptance;

import icky.imprecise;
import icky.circle;
import icky.packed;
import icky.packed_memory;

nothrow @nogc:
extern(C) uint oracle_decode(uint format, uint code);
extern(C) uint oracle_encode(uint format, uint bits);
extern(C) uint oracle_operation(uint format, uint operation, uint left, uint right);
extern(C) uint oracle_float16_chain(uint firstOperation, uint secondOperation,
                                    uint left, uint middle, uint right);
extern(C) uint oracle_packed_operation(uint left_format, uint right_format,
                                      uint operation, uint left, uint right);
extern(C) uint oracle_e5m3_operation(uint operation, uint left, uint right);
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

static assert(!__traits(compiles, E5M3.init + E5M3.init));
static assert(!__traits(compiles, E4M3.init + E5M2.init));
static assert(!__traits(compiles, Circle96.init + Circle96.init));
static assert(!__traits(compiles, rotate(Rotation192.init, Circle96.init)));
static assert(!__traits(compiles, Circle96.init.payload));
static assert(!__traits(compiles, Circle96(255)));
static assert(!__traits(compiles, E5M3.init.payload));

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

void check_storage()
{
    foreach (uint code; 0 .. 256)
    {
        auto value = E5M3.from_code(cast(ubyte)code);
        assert(bits_of(value.to_float()) == oracle_decode(4, code));
        E5M3 result;
        assert(E5M3.try_from_float(value.to_float(), result));
        assert(result.code() == code);
    }
    uint state = 0x735a2d97u;
    foreach (uint sample; 0 .. 16384)
    {
        state = state * 1664525u + 1013904223u;
        auto output = E5M3.from_code(73);
        uint expected = oracle_encode(4, state);
        bool accepted = E5M3.try_from_float(value_of(state), output);
        assert(accepted == (expected != 0x10000u));
        assert(output.code() == (accepted ? expected : 73));
    }
    foreach (uint bits; [0u, 0x80000000u, 1u, 0x37ffffffu, 0x38000000u,
                        0x47ffffffu, 0x48000000u, 0xbf800000u, 0x7f800000u,
                        0xff800000u, 0x7fc00000u])
    {
        auto output = E5M3.from_code(73);
        uint expected = oracle_encode(4, bits);
        bool accepted = E5M3.try_from_float(value_of(bits), output);
        assert(accepted == (expected != 0x10000u));
        assert(output.code() == (accepted ? expected : 73));
    }
}

void check_float16_random_operations()
{
    uint state = 0x91e10da5u;
    foreach (uint sample; 0 .. 65536)
    {
        state = state * 1664525u + 1013904223u;
        const ushort leftCode = cast(ushort)(state >> 16);
        state = state * 1664525u + 1013904223u;
        const ushort rightCode = cast(ushort)(state >> 16);
        auto left = Float16.from_code(leftCode);
        auto right = Float16.from_code(rightCode);
        Float16[4] results = [
            left + right,
            left - right,
            left * right,
            left / right
        ];
        foreach (uint operation; 0 .. 4)
        {
            const expected = oracle_operation(0, operation, leftCode, rightCode);
            if (nan_bits(oracle_decode(0, expected)))
                assert(nan_bits(bits_of(results[operation].to_float())));
            else
                assert(results[operation].code() == expected);
        }
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
    // E5M3/E5M3 + and - deliberately have no Float16-widening overload.
    static if (!(is(Left == E5M3) && is(Right == E5M3)))
    {
        check_packed_operation!("+")(left[], right[], leftFormat, rightFormat);
        check_packed_operation!("-")(left[], right[], leftFormat, rightFormat);
    }
    check_packed_operation!("*")(left[], right[], leftFormat, rightFormat);
    check_packed_operation!("/")(left[], right[], leftFormat, rightFormat);
}

void check_e5m3_direct_arithmetic()
{
    E5M3[256] values;
    foreach (uint code; 0 .. 256)
        values[code] = E5M3.from_code(cast(ubyte)code);

    foreach (uint left; 0 .. 256)
    foreach (uint right; 0 .. 256)
    {
        foreach (uint operation; 0 .. 3)
        {
            E5M3 result = E5M3.from_code(0x5a);
            bool accepted;
            switch (operation)
            {
                case 0:
                    accepted = E5M3.try_add(values[left], values[right], result);
                    break;
                case 1:
                    accepted = E5M3.try_subtract(values[left], values[right], result);
                    break;
                case 2:
                    accepted = E5M3.try_multiply(values[left], values[right], result);
                    break;
            }
            const expected = oracle_e5m3_operation(operation, left, right);
            assert(accepted == (expected != 0x10000u));
            assert(result.code() == (accepted ? expected : 0x5a));
        }
    }

    E5M3 output = E5M3.from_code(0x5a);
    assert(try_e5m3_at!("+")(values[], 80, values[], 81, output));
    assert(output.code() == oracle_e5m3_operation(0, 80, 81));
    const saved = output.code();
    assert(!try_e5m3_at!("-")(values[], 3, values[], 3, output));
    assert(output.code() == saved);
    assert(!try_e5m3_at!("+")(values[], 256, values[], 0, output));
    assert(output.code() == saved);
}

void check_packed_memory_surface()
{
    static assert(E5M3.sizeof == 1 && E3M2.sizeof == 1 && Float16.sizeof == 2);
    E5M3[2] adjacent_e5 = [E5M3.from_code(7), E5M3.from_code(9)];
    E3M2[2] adjacent_e3 = [E3M2.from_code(7), E3M2.from_code(9)];
    assert((&adjacent_e5[1] - &adjacent_e5[0]) == 1);
    assert((&adjacent_e3[1] - &adjacent_e3[0]) == 1);

    E5M3[256] e5;
    E3M2[256] e3;
    foreach (uint code; 0 .. 256)
    {
        e5[code] = E5M3.from_code(cast(ubyte)code);
        e3[code] = E3M2.from_code(cast(ubyte)code);
        assert(e3[code].code() == (code & 0x3fu));

        auto widened = Float16.from_float(e5[code].to_float());
        if (code < 248)
            assert((widened.code() & 0x7c00u) != 0x7c00u);
        else
            assert(widened.code() == 0x7c00u);
    }

    // Explicit Float16 compute remains available for multiplication/division
    // of E5M3 pairs and for all four operations on the mixed/signed formats.
    // E5M3/E5M3 + and - use the direct checked path instead.
    check_packed_operation_pairs!(E5M3, E5M3)(4, 4);
    check_packed_operation_pairs!(E5M3, E3M2)(4, 3);
    check_packed_operation_pairs!(E3M2, E5M3)(3, 4);
    check_packed_operation_pairs!(E3M2, E3M2)(3, 3);

    E5M3[1] one_e5 = [E5M3.from_code(120)];
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

    E5M3 exact_alias = E5M3.from_code(0x5a);
    assert(try_e5m3_at!("+")(one_e5[], 0, one_e5[], 0, exact_alias));
    assert(exact_alias.code() == oracle_e5m3_operation(
        0, one_e5[0].code(), one_e5[0].code()));

    // One coordinate, odd length, nonzero offset, final valid index and the
    // first and very large invalid indices all use the checked store surface.
    E5M3[5] sentinels = [E5M3.from_code(17), E5M3.from_code(31),
                         E5M3.from_code(47), E5M3.from_code(63),
                         E5M3.from_code(79)];
    auto odd = sentinels[1 .. 4];
    assert(try_store_at(odd, 2, Float16.from_float(2.0f)));
    assert(!try_store_at(odd, 3, Float16.from_float(2.0f)));
    assert(!try_store_at(odd, size_t.max, Float16.from_float(2.0f)));
    assert(sentinels[0].code() == 17 && sentinels[4].code() == 79);

    E5M3[1] one;
    assert(try_store_at(one[], 0, Float16.from_float(1.0f)));
    E5M3[0] empty;
    assert(!try_store_at(empty[], 0, Float16.from_float(1.0f)));

    // E5M3's partial encoder preserves the destination on every rejected
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
    E5M3[4] overlap = [E5M3.from_code(1), E5M3.from_code(2),
                       E5M3.from_code(3), E5M3.from_code(4)];
    auto first = overlap[0 .. 3];
    auto second = overlap[1 .. 4];
    E5M3 before = E5M3.from_code(0x5a);
    assert(try_e5m3_at!("+")(first, 1, second, 1, before));
    const expectedBefore = oracle_e5m3_operation(
        0, overlap[1].code(), overlap[2].code());
    assert(before.code() == expectedBefore);
    assert(try_store_at(second, 0, Float16.from_float(3.0f)));
    assert(overlap[1].code() == oracle_encode(4,
        bits_of(Float16.from_float(3.0f).to_float())));
    assert(overlap[0].code() == 1 && overlap[3].code() == 4);

    // A function address remains an ordinary callable D function.
    auto multiply = &compute_at!(Float16, "*", E5M3, E5M3);
    assert(multiply(first, 0, second, 0).code() ==
           oracle_packed_operation(4, 4, 2, overlap[0].code(), overlap[1].code()));
    auto store = &try_store_at!(E5M3);
    E5M3[1] address_destination = [E5M3.from_code(81)];
    assert(store(address_destination[], 0, Float16.from_float(1.0f)));
    assert(address_destination[0].code() == oracle_encode(4, bits_of(1.0f)));
}

void check_packed_memory()
{
    static assert(PackedValue!(E5M3, Float16).sizeof == E5M3.sizeof);
    static assert(PackedView!(E5M3, Float16, 8, 7).known_alignment == 8);
    static assert(PackedView!(E5M3, Float16, 8, 7).alias_set == 7);

    align(8) struct ByteBuffer { ubyte[512] data; }
    ByteBuffer buffer;
    foreach (size_t code; 0 .. 256)
        buffer.data[code * 2] = cast(ubyte)code;
    assert((cast(size_t)buffer.data.ptr & 7) == 0);
    auto view = PackedView!(E5M3, Float16, 8, 7)(
        buffer.data.ptr, buffer.data.length, 2);
    foreach (size_t code; 0 .. 256)
    {
        PackedValue!(E5M3, Float16) stored;
        assert(view.try_load(code, stored));
        assert(stored.stored.code() == code);
        auto widened = stored.decode();
        auto expectedWidened = Float16.from_float(value_of(oracle_decode(4, cast(uint)code)));
        assert(bits_of(widened.to_float()) == bits_of(expectedWidened.to_float()));

        // Some finite E5M3 extremes overflow the existing Float16 semantics.
        // Narrowing then follows E5M3's existing partial input-domain rule.
        const expectedCode = oracle_encode(4, bits_of(widened.to_float()));
        E5M3 encoded = E5M3.from_code(91);
        const accepted = PackedValue!(E5M3, Float16).try_encode(widened, encoded);
        assert(accepted == (expectedCode != 0x10000u));
        if (accepted) assert(encoded.code() == expectedCode);
        else assert(encoded.code() == 91);

        assert(view.try_store(code, widened) == accepted);
        assert(buffer.data[code * 2] == (accepted ? expectedCode : code));
    }

    // Failed bounds checks and failed E5M3-domain encodes preserve storage.
    PackedValue!(E5M3, Float16) unchanged = { E5M3.from_code(91) };
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
    auto unit = PackedView!(E5M3, Float16, 8, 0)(buffer.data.ptr, buffer.data.length, 1);
    auto arithmetic = Float16.from_float(2.0f) * Float16.from_float(1.5f);
    assert(unit.try_store(5, arithmetic));
    assert(buffer.data[5] == oracle_encode(4, bits_of(arithmetic.to_float())));
    PackedValue!(E5M3, Float16) product;
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

    puts("PASS: packed scalar load, explicit F16 widening, arithmetic, narrowing and store");
    puts("PASS: all 256 E5M3 encodings, non-unit stride, bounds, layout and memory facts");
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
    check_e5m3_direct_arithmetic();
    check_float16_random_operations();
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
    puts("PASS: all scalar payloads, native Float16 arithmetic, and boundary quantization against the C oracle");
    puts("PASS: exhaustive E5M3 +, -, and narrow * without Float16/binary32 arithmetic");
    check_grid!96();
    check_grid!192();
    check_grid!240();
    check_grid!360();
    check_grid!720();
    puts("PASS: finite-circle laws, canonical codes and the exact Circle96 C oracle");
    puts("PASS: forbidden E5M3 arithmetic and mixed geometric/scalar categories rejected");
    return 0;
}
