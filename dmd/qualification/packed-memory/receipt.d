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
    E5M3[8] destination;
    if (!packed_store_runtime(destination[], 3, product)) return 1;
    if (product.code() == quotient.code() || stream.code() == 0xffffu) return 2;
    return 0;
}
