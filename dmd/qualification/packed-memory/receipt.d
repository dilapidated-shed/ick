module packed_memory_receipt;

import icky.imprecise;
import icky.packed;
import icky.packed_memory;

extern(C) void packed_receipt(ubyte* bytes, size_t byteLength, size_t index)
    nothrow @nogc
{
    auto view = PackedView!(UE5M3, Float16, 1, 0)(bytes, byteLength, 1);
    PackedValue!(UE5M3, Float16) loaded;
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

extern(C) Float16 packed_multiply_runtime(
    const(UE5M3)[] left, size_t leftIndex,
    const(E3M2)[] right, size_t rightIndex)
    nothrow @nogc
{
    return compute_at!(Float16, "*")(left, leftIndex, right, rightIndex);
}

extern(C) Float16 packed_divide_runtime(
    const(UE5M3)[] left, size_t leftIndex,
    const(E3M2)[] right, size_t rightIndex)
    nothrow @nogc
{
    return compute_at!(Float16, "/")(left, leftIndex, right, rightIndex);
}

extern(C) bool packed_store_runtime(UE5M3[] destination, size_t index, Float16 value)
    nothrow @nogc
{
    return try_store_at(destination, index, value);
}

extern(C) E5M3 packed_signed_subtract_runtime(
    const(UE5M3)[] left, size_t leftIndex,
    const(UE5M3)[] right, size_t rightIndex)
    nothrow @nogc
{
    return compute_at!(E5M3, "-")(left, leftIndex, right, rightIndex);
}

extern(C) bool packed_signed_store_runtime(
    UE5M3[] destination, size_t index, E5M3 value)
    nothrow @nogc
{
    return try_store_at(destination, index, value);
}

extern(C) Float16 packed_stream_runtime(
    const(UE5M3)[] left, const(E3M2)[] right, size_t count)
    nothrow @nogc
{
    Float16 result = Float16.from_float(1.0f);
    foreach (size_t index; 0 .. count)
        result = compute_at!(Float16, "*")(left, index, right, index);
    return result;
}

extern(C) int main()
{
    UE5M3[8] left;
    E3M2[8] right;
    foreach (size_t index; 0 .. left.length)
    {
        left[index] = UE5M3.from_code(cast(ubyte)(index + 8));
        right[index] = E3M2.from_code(cast(ubyte)(index + 4));
    }
    auto product = packed_multiply_runtime(left[], 3, right[], 3);
    auto quotient = packed_divide_runtime(left[], 3, right[], 3);
    auto stream = packed_stream_runtime(left[], right[], left.length);
    UE5M3 signed_left;
    UE5M3 signed_right;
    if (!UE5M3.try_from_float(1.0f, signed_left)) return 1;
    if (!UE5M3.try_from_float(2.0f, signed_right)) return 2;
    UE5M3[1] signed_left_array = [signed_left];
    UE5M3[1] signed_right_array = [signed_right];
    auto difference = packed_signed_subtract_runtime(
        signed_left_array[], 0, signed_right_array[], 0);
    if (difference.code() != 0x178u) return 3;

    UE5M3[8] destination;
    if (!packed_store_runtime(destination[], 3, product)) return 4;
    destination[0] = UE5M3.from_code(73);
    if (packed_signed_store_runtime(destination[], 0, difference)) return 5;
    if (destination[0].code() != 73) return 6;
    if (product.code() == quotient.code() || stream.code() == 0xffffu) return 7;
    return 0;
}
