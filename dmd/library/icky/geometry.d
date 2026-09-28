/** Geometric value representations for the portable DMD follower.
 * Storage is explicit; this module does not claim new primitive compiler types.
 * All arithmetic and normalization work is binary32, never binary64.
 */
module icky.geometry;

import core.stdc.math : sqrtf, fabsf;
import icky.imprecise : Float16, E4M3, E5M2, E3M2;

nothrow @nogc:

package bool finite_float(float value)
{
    return value == value && value <= float.max && value >= -float.max;
}

package bool normalize_components(size_t count)(float[count] input,
                                               ref float[count] output)
{
    float largest = 0.0f;
    foreach (value; input)
    {
        if (!finite_float(value)) return false;
        if (fabsf(value) > largest) largest = fabsf(value);
    }
    if (largest == 0.0f) return false;
    float[count] scaled;
    float squared_length = 0.0f;
    foreach (index; 0 .. count)
    {
        // Division, rather than multiplication by a reciprocal, also works
        // for finite subnormal inputs and for inputs close to float.max.
        scaled[index] = input[index] / largest;
        squared_length += scaled[index] * scaled[index];
    }
    float length = sqrtf(squared_length);
    foreach (ref value; scaled) value /= length;
    output = scaled;
    return true;
}

private enum compact_component(Component) =
    is(Component == Float16) || is(Component == E4M3) ||
    is(Component == E5M2) || is(Component == E3M2);

private Component store_component(Component)(float value)
{
    static if (is(Component == float)) return value;
    else return Component.from_float(value);
}
private float load_component(Component)(Component value)
{
    static if (is(Component == float)) return value;
    else return value.to_float();
}

/** Hamilton algebra. Coefficient order is real, i, j, k.
 * A complete algebra operation evaluates in binary32, then rounds each output
 * coefficient once to Component. Chained algebra operations keep that boundary.
 */
struct Quaternion(Component = Float16)
    if (is(Component == float) || compact_component!Component)
{
    nothrow @nogc:
    static if (is(Component == float)) private float[4] values = 0.0f;
    else private Component[4] values;

    static Quaternion from_components(float real, float i, float j, float k)
    {
        Quaternion result;
        result.values = [store_component!Component(real), store_component!Component(i),
                         store_component!Component(j), store_component!Component(k)];
        return result;
    }
    float[4] components() const
    {
        float[4] result;
        foreach (index; 0 .. 4) result[index] = load_component!Component(values[index]);
        return result;
    }
    Quaternion conjugate() const
    {
        auto value = components();
        return from_components(value[0], -value[1], -value[2], -value[3]);
    }
    Quaternion opUnary(string operation)() const if (operation == "-")
    {
        auto value = components();
        return from_components(-value[0], -value[1], -value[2], -value[3]);
    }
    Quaternion opBinary(string operation)(Quaternion other) const
        if (operation == "+" || operation == "-" || operation == "*")
    {
        auto left = components();
        auto right = other.components();
        static if (operation == "+")
            return from_components(left[0]+right[0], left[1]+right[1],
                                   left[2]+right[2], left[3]+right[3]);
        else static if (operation == "-")
            return from_components(left[0]-right[0], left[1]-right[1],
                                   left[2]-right[2], left[3]-right[3]);
        else
            return from_components(
                ((left[0]*right[0] - left[1]*right[1]) - left[2]*right[2]) - left[3]*right[3],
                ((left[0]*right[1] + left[1]*right[0]) + left[2]*right[3]) - left[3]*right[2],
                ((left[0]*right[2] - left[1]*right[3]) + left[2]*right[0]) + left[3]*right[1],
                ((left[0]*right[3] + left[1]*right[2]) - left[2]*right[1]) + left[3]*right[0]);
    }
    bool try_inverse(ref Quaternion output) const
    {
        auto value = components();
        float largest = 0.0f;
        foreach (part; value)
        {
            if (!finite_float(part)) return false;
            if (fabsf(part) > largest) largest = fabsf(part);
        }
        if (largest == 0.0f) return false;
        float squared_length = 0.0f;
        foreach (ref part; value)
        {
            part /= largest;
            squared_length += part * part;
        }
        foreach (index; 0 .. 4)
        {
            value[index] = (value[index] / squared_length) / largest;
            if (index != 0) value[index] = -value[index];
            if (!finite_float(value[index])) return false;
        }
        auto candidate = from_components(value[0], value[1], value[2], value[3]);
        foreach (part; candidate.components()) if (!finite_float(part)) return false;
        output = candidate;
        return true;
    }
}

alias HH = Quaternion!Float16;
alias HH32 = Quaternion!float;
alias hh = HH;

/** A numerically normalized point on S3. Default initialization is identity.
 * q and -q remain different S3 points; rotation_distance identifies their actions.
 */
struct UnitQuaternion
{
    nothrow @nogc:
    private float[4] values = [1.0f, 0.0f, 0.0f, 0.0f];

    static bool try_from_components(float real, float i, float j, float k,
                                    ref UnitQuaternion output)
    {
        float[4] normalized;
        if (!normalize_components!4([real, i, j, k], normalized)) return false;
        UnitQuaternion candidate;
        candidate.values = normalized;
        output = candidate;
        return true;
    }
    static bool try_from_quaternion(Component)(Quaternion!Component input,
                                               ref UnitQuaternion output)
    {
        auto value = input.components();
        return try_from_components(value[0], value[1], value[2], value[3], output);
    }
    float[4] components() const { return values; }
    HH32 as_quaternion() const
    {
        return HH32.from_components(values[0], values[1], values[2], values[3]);
    }
    UnitQuaternion inverse() const
    {
        UnitQuaternion result;
        result.values = [values[0], -values[1], -values[2], -values[3]];
        return result;
    }
    UnitQuaternion opUnary(string operation)() const if (operation == "-")
    {
        UnitQuaternion result;
        foreach (index; 0 .. 4) result.values[index] = -values[index];
        return result;
    }
    UnitQuaternion opBinary(string operation)(UnitQuaternion other) const
        if (operation == "*")
    {
        UnitQuaternion result;
        bool valid = try_from_quaternion(as_quaternion() * other.as_quaternion(), result);
        assert(valid);
        return result;
    }
    float s3_distance(UnitQuaternion other) const
    {
        float sum = 0.0f;
        foreach (index; 0 .. 4)
        {
            float difference = values[index] - other.values[index];
            sum += difference * difference;
        }
        return sqrtf(sum);
    }
    // Chord distance modulo the antipodal identification, not an angle.
    float rotation_distance(UnitQuaternion other) const
    {
        float same_sign = s3_distance(other);
        float opposite_sign = s3_distance(-other);
        return same_sign < opposite_sign ? same_sign : opposite_sign;
    }
}

/** Rounded components are not called exactly unit. Reconstruction and the
 * observed radial error are explicit; default initialization is identity.
 */
struct ApproxUnitQuaternion(Component = Float16) if (compact_component!Component)
{
    nothrow @nogc:
    private static Component one()
    {
        static if (is(Component == Float16)) return Component.from_code(cast(ushort)0x3c00);
        else static if (is(Component == E4M3)) return Component.from_code(cast(ubyte)0x38);
        else static if (is(Component == E5M2)) return Component.from_code(cast(ubyte)0x3c);
        else return Component.from_code(cast(ubyte)0x0c);
    }
    private Component[4] rounded = [one(), Component.init, Component.init, Component.init];
    static ApproxUnitQuaternion from_unit(UnitQuaternion input)
    {
        ApproxUnitQuaternion result;
        auto value = input.components();
        foreach (index; 0 .. 4) result.rounded[index] = Component.from_float(value[index]);
        return result;
    }
    Quaternion!Component as_quaternion() const
    {
        Quaternion!Component result;
        result.values = rounded;
        return result;
    }
    float radial_error() const
    {
        float sum = 0.0f;
        foreach (part; rounded)
        {
            float value = part.to_float();
            sum += value * value;
        }
        return fabsf(sqrtf(sum) - 1.0f);
    }
    UnitQuaternion reconstruct() const
    {
        UnitQuaternion result;
        bool valid = UnitQuaternion.try_from_quaternion(as_quaternion(), result);
        assert(valid);
        return result;
    }
}

struct Unframed {}

/** S2 direction, not S3 orientation. Only explicit normalization constructs it. */
struct Direction(Frame = Unframed)
{
    nothrow @nogc:
    private float[3] values = [1.0f, 0.0f, 0.0f];
    static bool try_from_components(float x, float y, float z, ref Direction output)
    {
        float[3] normalized;
        if (!normalize_components!3([x, y, z], normalized)) return false;
        Direction candidate;
        candidate.values = normalized;
        output = candidate;
        return true;
    }
    float[3] components() const { return values; }
    HH32 as_pure_quaternion() const
    {
        return HH32.from_components(0.0f, values[0], values[1], values[2]);
    }
    static bool try_from_pure_quaternion(HH32 input, ref Direction output)
    {
        auto value = input.components();
        if (value[0] != 0.0f) return false;
        return try_from_components(value[1], value[2], value[3], output);
    }
    float distance(Direction other) const
    {
        float sum = 0.0f;
        foreach (index; 0 .. 3)
        {
            float difference = values[index] - other.values[index];
            sum += difference * difference;
        }
        return sqrtf(sum);
    }
}
alias S2 = Direction!Unframed;

/** An active, right-handed rotation carrying Source coordinates to Destination.
 * first.then(next) applies first, then next: its quaternion is next * first.
 */
struct SpatialRotation(Source = Unframed, Destination = Unframed)
{
    nothrow @nogc:
    private UnitQuaternion orientation;
    static SpatialRotation from_unit(UnitQuaternion value)
    {
        SpatialRotation result;
        result.orientation = value;
        return result;
    }
    UnitQuaternion as_unit() const { return orientation; }
    SpatialRotation!(Source, Next) then(Next)(SpatialRotation!(Destination, Next) next) const
    {
        return SpatialRotation!(Source, Next).from_unit(next.orientation * orientation);
    }
    SpatialRotation!(Destination, Source) inverse() const
    {
        return SpatialRotation!(Destination, Source).from_unit(orientation.inverse());
    }
    Direction!Destination apply(Direction!Source input) const
    {
        auto rotated = (orientation.as_quaternion() * input.as_pure_quaternion()) *
                        orientation.inverse().as_quaternion();
        auto value = rotated.components();
        Direction!Destination result;
        bool valid = Direction!Destination.try_from_components(value[1], value[2], value[3], result);
        assert(valid);
        return result;
    }
}
alias SO3 = SpatialRotation!(Unframed, Unframed);

/** Smallest-three packing reuses the existing scalar quantizers.
 * Bits 0..1 select the largest absolute component (first index wins ties).
 * Negate all components when that component is negative. In increasing index
 * order, multiply each retained component by sqrt(2), then quantize it.
 * Subsequent bits hold the three scalar codes, low bit first; unused bits are 0.
 * This is an explicit new follower wire layout, not a claim of compatibility
 * with a separately deployed codec. Scalar rounding stays in icky.imprecise.
 */
struct SmallestThree(Component = Float16) if (compact_component!Component)
{
    nothrow @nogc:
    static if (is(Component == Float16)) enum uint component_bits = 16;
    else static if (is(Component == E3M2)) enum uint component_bits = 6;
    else enum uint component_bits = 8;
    enum uint used_bits = 2 + 3 * component_bits;
    enum uint byte_count = (used_bits + 7) / 8;
    static if (is(Component == Float16)) enum float component_error = 0.000244140625f;
    else static if (is(Component == E4M3)) enum float component_error = 0.03125f;
    else enum float component_error = 0.0625f;
    // Conservative S3 chord bound, with an explicit binary32 rounding allowance.
    enum float chord_error_bound = 4.898979486f * component_error + 0.000004f;
    private ubyte[byte_count] payload;

    private void write_field(uint offset, uint width, uint value)
    {
        foreach (bit; 0 .. width)
            if (value & (1u << bit))
                payload[(offset + bit) / 8] |= cast(ubyte)(1u << ((offset + bit) % 8));
    }
    private uint read_field(uint offset, uint width) const
    {
        uint result = 0;
        foreach (bit; 0 .. width)
            if (payload[(offset + bit) / 8] & (1u << ((offset + bit) % 8))) result |= 1u << bit;
        return result;
    }
    static SmallestThree from_unit(UnitQuaternion input)
    {
        auto value = input.components();
        uint omitted = 0;
        foreach (index; 1 .. 4)
            if (fabsf(value[index]) > fabsf(value[omitted])) omitted = cast(uint)index;
        if (value[omitted] < 0.0f) foreach (ref part; value) part = -part;
        SmallestThree result;
        result.write_field(0, 2, omitted);
        uint offset = 2;
        foreach (index; 0 .. 4)
        {
            if (index == omitted) continue;
            auto compact = Component.from_float(value[index] * 1.4142135623730951f);
            result.write_field(offset, component_bits, compact.code());
            offset += component_bits;
        }
        return result;
    }
    ubyte[byte_count] code() const { return payload; }
    uint omitted_index() const { return read_field(0, 2); }
    static bool try_from_code(ubyte[byte_count] input, ref SmallestThree output)
    {
        SmallestThree candidate;
        candidate.payload = input;
        UnitQuaternion reconstructed;
        if (!candidate.try_reconstruct(reconstructed)) return false;
        output = candidate;
        return true;
    }
    bool try_reconstruct(ref UnitQuaternion output) const
    {
        static if (used_bits % 8 != 0)
            if ((payload[byte_count - 1] >> (used_bits % 8)) != 0) return false;
        float[4] value = 0.0f;
        uint omitted = omitted_index();
        uint offset = 2;
        float retained_squared = 0.0f;
        foreach (index; 0 .. 4)
        {
            if (index == omitted) continue;
            uint raw = read_field(offset, component_bits);
            static if (is(Component == Float16)) auto compact = Component.from_code(cast(ushort)raw);
            else auto compact = Component.from_code(cast(ubyte)raw);
            float scaled = compact.to_float();
            if (!finite_float(scaled) || fabsf(scaled) > 1.0f) return false;
            value[index] = scaled * 0.7071067811865475f;
            retained_squared += value[index] * value[index];
            offset += component_bits;
        }
        if (retained_squared > 1.0f) return false;
        value[omitted] = sqrtf(1.0f - retained_squared);
        return UnitQuaternion.try_from_components(value[0], value[1], value[2], value[3], output);
    }
    UnitQuaternion reconstruct() const
    {
        UnitQuaternion result;
        bool valid = try_reconstruct(result);
        assert(valid);
        return result;
    }
}

static assert(HH.sizeof == 8 && HH32.sizeof == 16);
static assert(SmallestThree!Float16.sizeof == 7);
static assert(SmallestThree!E4M3.sizeof == 4 && SmallestThree!E5M2.sizeof == 4);
static assert(SmallestThree!E3M2.sizeof == 3);
static assert(!is(S2 == UnitQuaternion) && !is(HH == UnitQuaternion));
