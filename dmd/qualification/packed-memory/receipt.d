module packed_memory_receipt;

import icky.imprecise;
import icky.packed;

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
