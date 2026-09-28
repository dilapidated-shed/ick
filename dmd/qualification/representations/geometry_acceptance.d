module geometry_acceptance;

import core.stdc.math : sqrtf, fabsf;
import icky.imprecise;
import icky.geometry;
import icky.projective;

nothrow @nogc:
extern(C) int puts(const char* text);
extern(C) void geometry_oracle_rotate(const float* quaternion, const float* point, float* output);

struct Phone {}
struct Room {}
struct Camera {}
alias FourFloats = float[4];
alias ThreeFloats = float[3];
alias ProjectiveCoordinates = Complex32[3];
alias PackedHalf = SmallestThree!Float16;
alias PackedHalfBytes = ubyte[7];

static assert(!__traits(compiles, HH.init + UnitQuaternion.init));
static assert(!__traits(compiles, Quaternion!E5M3.init));
static assert(!__traits(compiles, SmallestThree!E5M3.init));
static assert(!__traits(compiles, UnitQuaternion.init.values));
static assert(!__traits(compiles, UnitQuaternion(FourFloats.init)));
static assert(!__traits(compiles, S2(ThreeFloats.init)));
static assert(!__traits(compiles, PackedHalf(PackedHalfBytes.init)));
static assert(!__traits(compiles, CP2(ProjectiveCoordinates.init)));
static assert(!__traits(compiles, CP2.init.representative));
static assert(!__traits(compiles, CP2.init == CP2.init));
static assert(!__traits(compiles, SO3.init == SO3.init));
static assert(!__traits(compiles, CP1.init.distance(CP2.init)));
static assert(!__traits(compiles, S2.init.distance(Direction!Phone.init)));
static assert(!__traits(compiles,
    SpatialRotation!(Phone, Room).init.apply(Direction!Camera.init)));
static assert(!__traits(compiles,
    SpatialRotation!(Phone, Room).init.then(SpatialRotation!(Camera, Phone).init)));
static assert(is(typeof(SpatialRotation!(Phone, Room).init.then(
    SpatialRotation!(Room, Camera).init)) == SpatialRotation!(Phone, Camera)));

private union FloatBits { uint bits; float value; }
private float from_bits(uint bits)
{
    FloatBits result;
    result.bits = bits;
    return result.value;
}
private float next_component(ref uint state)
{
    state = state * 1664525u + 1013904223u;
    return cast(float)(cast(int)(state >> 8) - 8388608) / 8388608.0f;
}
private void near(float got, float expected, float tolerance = 0.000003f)
{
    assert(got == got && fabsf(got - expected) <= tolerance);
}
private void assert_four_equal(float[4] left, float[4] right)
{
    foreach (index; 0 .. 4) assert(left[index] == right[index]);
}
private void assert_three_equal(float[3] left, float[3] right)
{
    foreach (index; 0 .. 3) assert(left[index] == right[index]);
}
private void assert_complex_equal(size_t count)(Complex32[count] left, Complex32[count] right)
{
    foreach (index; 0 .. count)
    {
        assert(left[index].real_part == right[index].real_part);
        assert(left[index].imaginary_part == right[index].imaginary_part);
    }
}
private void assert_bytes_equal(size_t count)(ubyte[count] left, ubyte[count] right)
{
    foreach (index; 0 .. count) assert(left[index] == right[index]);
}
private void check_unit(UnitQuaternion value)
{
    float squared = 0.0f;
    foreach (part; value.components()) squared += part * part;
    near(squared, 1.0f, 0.000002f);
}
private UnitQuaternion unit(float w, float x, float y, float z)
{
    UnitQuaternion result;
    bool valid = UnitQuaternion.try_from_components(w, x, y, z, result);
    assert(valid);
    return result;
}

void algebra(Component)()
{
    alias Q = Quaternion!Component;
    auto one = Q.from_components(1.0f, 0.0f, 0.0f, 0.0f);
    auto i = Q.from_components(0.0f, 1.0f, 0.0f, 0.0f);
    auto j = Q.from_components(0.0f, 0.0f, 1.0f, 0.0f);
    auto k = Q.from_components(0.0f, 0.0f, 0.0f, 1.0f);
    assert_four_equal((i*j).components(), k.components());
    assert_four_equal((j*i).components(), (-k).components());
    assert_four_equal((i*i).components(), (-one).components());
    assert_four_equal(((i*j)*k).components(), (-one).components());
    assert_four_equal((i + j - j).components(), i.components());
    assert_four_equal((one*k).components(), k.components());
}

void normalization_and_frames()
{
    auto identity = UnitQuaternion.init;
    check_unit(identity);
    auto value = unit(1.0f, 2.0f, -3.0f, 4.0f);
    near((value * value.inverse()).rotation_distance(identity), 0.0f);
    near(value.rotation_distance(-value), 0.0f);
    near(value.s3_distance(-value), 2.0f);
    near(SO3.from_unit(value).distance(SO3.from_unit(-value)), 0.0f);
    check_unit(unit(float.max, float.max, float.max, float.max));
    check_unit(unit(from_bits(1), from_bits(1), 0.0f, 0.0f));
    auto sentinel = value;
    assert(!UnitQuaternion.try_from_components(0.0f, 0.0f, 0.0f, 0.0f, sentinel));
    assert_four_equal(sentinel.components(), value.components());
    assert(!UnitQuaternion.try_from_components(float.infinity, 1.0f, 0.0f, 0.0f, sentinel));
    assert(!UnitQuaternion.try_from_components(float.nan, 1.0f, 0.0f, 0.0f, sentinel));
    assert_four_equal(sentinel.components(), value.components());

    auto q = HH32.from_components(1.0f, 2.0f, 3.0f, 4.0f);
    HH32 inverse = q;
    assert(q.try_inverse(inverse));
    auto product = (q * inverse).components();
    near(product[0], 1.0f);
    foreach (index; 1 .. 4) near(product[index], 0.0f);
    auto saved_inverse = inverse;
    assert(!HH32.init.try_inverse(inverse));
    assert_four_equal(inverse.components(), saved_inverse.components());

    Direction!Phone x = Direction!Phone.init;
    assert(Direction!Phone.try_from_components(1.0f, 0.0f, 0.0f, x));
    auto z_turn = SpatialRotation!(Phone, Room).from_unit(unit(1.0f, 0.0f, 0.0f, 1.0f));
    auto x_turn = SpatialRotation!(Room, Camera).from_unit(unit(1.0f, 1.0f, 0.0f, 0.0f));
    auto y = z_turn.apply(x).components();
    near(y[0], 0.0f); near(y[1], 1.0f); near(y[2], 0.0f);
    auto combined = z_turn.then(x_turn);
    auto z = combined.apply(x);
    near(z.components()[0], 0.0f); near(z.components()[1], 0.0f); near(z.components()[2], 1.0f);
    near(z.distance(x_turn.apply(z_turn.apply(x))), 0.0f);
    near(combined.inverse().apply(z).distance(x), 0.0f);

    S2 direction = S2.init;
    assert(S2.try_from_components(float.max, -float.max, float.max, direction));
    S2 decoded = S2.init;
    assert(S2.try_from_pure_quaternion(direction.as_pure_quaternion(), decoded));
    near(direction.distance(decoded), 0.0f);
    auto saved_direction = decoded;
    assert(!S2.try_from_pure_quaternion(HH32.from_components(1.0f, 1.0f, 0.0f, 0.0f), decoded));
    assert(!S2.try_from_components(0.0f, 0.0f, 0.0f, decoded));
    assert(!S2.try_from_components(float.nan, 0.0f, 0.0f, decoded));
    assert_three_equal(decoded.components(), saved_direction.components());

    uint state = 415u;
    foreach (sample; 0 .. 4096)
    {
        auto rotation = unit(next_component(state), next_component(state),
                             next_component(state), next_component(state));
        S2 input = S2.init;
        assert(S2.try_from_components(next_component(state), next_component(state),
                                     next_component(state), input));
        auto got = SO3.from_unit(rotation).apply(input).components();
        auto qparts = rotation.components();
        auto point = input.components();
        float[3] expected = void;
        geometry_oracle_rotate(qparts.ptr, point.ptr, expected.ptr);
        foreach (index; 0 .. 3) near(got[index], expected[index], 0.000004f);
    }
    puts("PASS: Hamilton algebra, robust normalization, S2, typed composition and independent matrix action");
}

void put_bits(size_t count)(ref ubyte[count] bytes, uint offset, uint width, uint value)
{
    foreach (bit; 0 .. width)
        if (value & (1u << bit)) bytes[(offset+bit)/8] |= cast(ubyte)(1u << ((offset+bit)%8));
}

void packed_quaternions(Component)()
{
    alias Packed = SmallestThree!Component;
    auto identity = Packed.from_unit(UnitQuaternion.init);
    foreach (part; identity.code()) assert(part == 0);
    foreach (uint index; 0 .. 4)
    {
        float[4] axis = [0.0f, 0.0f, 0.0f, 0.0f];
        axis[index] = -1.0f;
        auto value = unit(axis[0], axis[1], axis[2], axis[3]);
        auto packed = Packed.from_unit(value);
        assert(packed.omitted_index() == index);
        near(packed.reconstruct().rotation_distance(value), 0.0f);
    }
    auto equal_parts = unit(1.0f, 1.0f, 1.0f, 1.0f);
    auto equal_packed = Packed.from_unit(equal_parts);
    assert(equal_packed.omitted_index() == 0);
    static if (is(Component == Float16))
        assert_bytes_equal(equal_packed.code(), cast(ubyte[7])[0xa0,0xe6,0xa0,0xe6,0xa0,0xe6,0]);
    static if (is(Component == Float16)) enum uint one_code = 0x3c00;
    else static if (is(Component == E4M3)) enum uint one_code = 0x38;
    else static if (is(Component == E5M2)) enum uint one_code = 0x3c;
    else enum uint one_code = 0x0c;

    auto retained_output = equal_packed;
    auto reserved = identity.code();
    reserved[Packed.byte_count - 1] |= 0x80;
    assert(!Packed.try_from_code(reserved, retained_output));
    assert_bytes_equal(retained_output.code(), equal_packed.code());
    ubyte[Packed.byte_count] impossible;
    foreach (uint index; 0 .. 3)
        put_bits(impossible, 2 + index * Packed.component_bits, Packed.component_bits, one_code);
    assert(!Packed.try_from_code(impossible, retained_output));
    assert_bytes_equal(retained_output.code(), equal_packed.code());
    static if (is(Component == Float16) || is(Component == E4M3) || is(Component == E5M2))
    {
        ubyte[Packed.byte_count] nonfinite;
        static if (is(Component == Float16)) enum uint nan_code = 0x7e00;
        else enum uint nan_code = 0x7f;
        put_bits(nonfinite, 2, Packed.component_bits, nan_code);
        assert(!Packed.try_from_code(nonfinite, retained_output));
    }

    uint state = 72431u;
    foreach (sample; 0 .. 131072)
    {
        auto value = unit(next_component(state), next_component(state),
                          next_component(state), next_component(state));
        auto packed = Packed.from_unit(value);
        assert_bytes_equal(packed.code(), Packed.from_unit(-value).code());
        Packed from_wire;
        assert(Packed.try_from_code(packed.code(), from_wire));
        auto reconstructed = from_wire.reconstruct();
        check_unit(reconstructed);
        assert(value.rotation_distance(reconstructed) <= Packed.chord_error_bound);
        auto rounded = ApproxUnitQuaternion!Component.from_unit(value);
        assert(rounded.radial_error() <= 2.0f * Packed.component_error + 0.000004f);
        check_unit(rounded.reconstruct());
    }
    check_unit(ApproxUnitQuaternion!Component.init.reconstruct());
    puts("PASS: 131072 quaternion samples; sign quotient, wire reconstruction, norm and error bounds");
}

void projective_family(size_t dimension)()
{
    alias Point = CPn!dimension;
    uint state = 18181u;
    foreach (sample; 0 .. 1024)
    {
        Complex32[dimension + 1] input;
        foreach (ref coordinate; input)
            coordinate = Complex32(next_component(state), next_component(state));
        Point original;
        assert(Point.try_from_homogeneous(input, original));
        Complex32[4] scales = [Complex32(-3.0f, 2.0f), Complex32(0.0f, 8.0f),
            Complex32(0x1p-100f, 0.0f), Complex32(0x1p100f, -0x1p100f)];
        foreach (scale; scales)
        {
            Complex32[dimension + 1] scaled;
            foreach (index; 0 .. dimension + 1) scaled[index] = input[index] * scale;
            Point changed;
            assert(Point.try_from_homogeneous(scaled, changed));
            assert(original.same_point(changed, 0.000003f));
        }
        float squared = 0.0f;
        foreach (coordinate; original.homogeneous_coordinates())
            squared += coordinate.real_part * coordinate.real_part +
                       coordinate.imaginary_part * coordinate.imaginary_part;
        near(squared, 1.0f);
    }
}

void projective_geometry()
{
    CP2 first, second;
    Complex32[3] e0 = [Complex32(1.0f,0.0f), Complex32(), Complex32()];
    Complex32[3] e1 = [Complex32(), Complex32(1.0f,0.0f), Complex32()];
    assert(CP2.try_from_homogeneous(e0, first));
    assert(CP2.try_from_homogeneous(e1, second));
    near(first.distance(second), 1.0f);
    assert(!first.same_point(second, 0.001f));
    assert(!first.same_point(first, -0.001f));
    assert(!first.same_point(first, float.nan));
    Complex32[3] line = [Complex32(1.0f,0.0f), Complex32(0.0f,1.0f), Complex32()];
    assert(CP2.try_from_homogeneous(line, second));
    near(first.distance(second), sqrtf(0.5f));
    Complex32[2] chart;
    assert(second.try_chart(0, chart));
    near(chart[0].real_part, 0.0f); near(chart[0].imaginary_part, 1.0f);
    near(chart[1].real_part, 0.0f); near(chart[1].imaginary_part, 0.0f);
    auto saved_chart = chart;
    assert(!second.try_chart(2, chart));
    assert(!second.try_chart(3, chart));
    assert_complex_equal(chart, saved_chart);

    auto saved = second.homogeneous_coordinates();
    Complex32[3] invalid;
    assert(!CP2.try_from_homogeneous(invalid, second));
    invalid[1] = Complex32(0.0f, float.infinity);
    assert(!CP2.try_from_homogeneous(invalid, second));
    invalid[1] = Complex32(float.nan, 0.0f);
    assert(!CP2.try_from_homogeneous(invalid, second));
    assert_complex_equal(second.homogeneous_coordinates(), saved);

    Complex32[3] extreme = [Complex32(float.max,float.max), Complex32(-float.max,0.0f), Complex32()];
    assert(CP2.try_from_homogeneous(extreme, second));
    extreme = [Complex32(from_bits(1),0.0f), Complex32(), Complex32()];
    assert(CP2.try_from_homogeneous(extreme, second));
    near(first.distance(second), 0.0f);
    projective_family!0();
    projective_family!1();
    projective_family!2();
    projective_family!4();
    puts("PASS: CP0/CP1/CP2/CP4, complex rescaling and phase, charts, distinct points and invalid inputs");
}

extern(C) int main()
{
    algebra!float(); algebra!Float16(); algebra!E4M3(); algebra!E5M2(); algebra!E3M2();
    normalization_and_frames();
    packed_quaternions!Float16(); packed_quaternions!E4M3();
    packed_quaternions!E5M2(); packed_quaternions!E3M2();
    projective_geometry();
    puts("PASS: geometric D value representations; not primitive-backend or Android acceptance");
    return 0;
}
