module packed_memory_receipt;

import icky.imprecise;
import icky.packed;
import icky.packed_memory;

extern(C) void packed_receipt(ubyte* bytes, size_t byteLength, size_t index)
    nothrow @nogc
{
    auto view = PackedView!(E5M3, Float16, 1, 0)(bytes, byteLength, 1);
    PackedValue!(E5M3, Float16) loaded;
    if (!view.try_load(index, loaded))
        return;

    auto arithmetic = loaded.decode() * Float16.from_float(2.0f);
    view.try_store(index, arithmetic);
}

extern(C) float ordinary_float_receipt(float left, float right) nothrow @nogc
{
    return left * right + 1.0f;
}

extern(C) Float16 ordinary_half_receipt(Float16 left, Float16 right)
    nothrow @nogc
{
    return left * right;
}

extern(C) bool packed_e5_add_runtime(
    const(E5M3)[] left, size_t leftIndex,
    const(E5M3)[] right, size_t rightIndex,
    ref E5M3 output)
    nothrow @nogc
{
    return try_e5m3_at!("+")(left, leftIndex, right, rightIndex, output);
}

extern(C) bool packed_e5_subtract_runtime(
    const(E5M3)[] left, size_t leftIndex,
    const(E5M3)[] right, size_t rightIndex,
    ref E5M3 output)
    nothrow @nogc
{
    return try_e5m3_at!("-")(left, leftIndex, right, rightIndex, output);
}

extern(C) bool packed_e5_multiply_narrow_runtime(
    const(E5M3)[] left, size_t leftIndex,
    const(E5M3)[] right, size_t rightIndex,
    ref E5M3 output)
    nothrow @nogc
{
    return try_e5m3_at!("*")(left, leftIndex, right, rightIndex, output);
}

extern(C) Float16 packed_multiply_runtime(
    const(E5M3)[] left, size_t leftIndex,
    const(E3M2)[] right, size_t rightIndex)
    nothrow @nogc
{
    return compute_at!(Float16, "*")(left, leftIndex, right, rightIndex);
}

extern(C) Float16 packed_divide_runtime(
    const(E5M3)[] left, size_t leftIndex,
    const(E3M2)[] right, size_t rightIndex)
    nothrow @nogc
{
    return compute_at!(Float16, "/")(left, leftIndex, right, rightIndex);
}

extern(C) bool packed_store_runtime(E5M3[] destination, size_t index, Float16 value)
    nothrow @nogc
{
    return try_store_at(destination, index, value);
}

extern(C) Float16 packed_stream_runtime(
    const(E5M3)[] left, const(E3M2)[] right, size_t count)
    nothrow @nogc
{
    Float16 result = Float16.from_float(1.0f);
    foreach (size_t index; 0 .. count)
        result = compute_at!(Float16, "*")(left, index, right, index);
    return result;
}

extern(C) int main()
{
    E5M3[8] left;
    E3M2[8] right;
    foreach (size_t index; 0 .. left.length)
    {
        left[index] = E5M3.from_code(cast(ubyte)(index + 8));
        right[index] = E3M2.from_code(cast(ubyte)(index + 4));
    }
    auto product = packed_multiply_runtime(left[], 3, right[], 3);
    auto quotient = packed_divide_runtime(left[], 3, right[], 3);
    auto stream = packed_stream_runtime(left[], right[], left.length);

    E5M3 direct = E5M3.from_code(0x5a);
    if (!packed_e5_add_runtime(left[], 3, left[], 4, direct)) return 1;

    // These tiny operands put subtraction and multiplication below the
    // positive E5M3 domain. Rejection must preserve the destination.
    direct = E5M3.from_code(0x5a);
    if (packed_e5_subtract_runtime(left[], 4, left[], 3, direct)) return 2;
    if (direct.code() != 0x5a) return 6;
    if (packed_e5_multiply_narrow_runtime(left[], 3, left[], 4, direct)) return 3;
    if (direct.code() != 0x5a) return 7;

    // Use ordinary in-range payloads for the successful arithmetic receipt.
    E5M3[2] in_range_operands = [E5M3.from_code(0x78), E5M3.from_code(0x80)];
    if (!packed_e5_subtract_runtime(in_range_operands[], 1, in_range_operands[], 0, direct)) return 8;
    if (!packed_e5_multiply_narrow_runtime(in_range_operands[], 0, in_range_operands[], 1, direct)) return 9;

    E5M3[8] destination;
    if (!packed_store_runtime(destination[], 3, product)) return 4;
    if (product.code() == quotient.code() || stream.code() == 0xffffu) return 5;
    return 0;
}
