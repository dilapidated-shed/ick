module representation_acceptance;

import icky.imprecise;
import icky.circle;

nothrow @nogc:
extern(C) uint oracle_decode(uint format, uint code);
extern(C) uint oracle_encode(uint format, uint bits);
extern(C) uint oracle_operation(uint format, uint operation, uint left, uint right);
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
    puts("PASS: all scalar payloads, boundary quantization and arithmetic against the C oracle");
    check_grid!96();
    check_grid!192();
    check_grid!240();
    check_grid!360();
    check_grid!720();
    puts("PASS: finite-circle laws, canonical codes and the exact Circle96 C oracle");
    puts("PASS: forbidden E5M3 arithmetic and mixed geometric/scalar categories rejected");
    return 0;
}
