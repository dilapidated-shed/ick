module packed_memory_bounds;

import icky.imprecise;
import icky.packed_memory;

extern(C) uint oracle_encode(uint format, uint bits) nothrow @nogc;

nothrow @nogc:

extern(C) int main()
{
    // This executable is built with D bounds and assertions disabled.  The
    // public checked store must still reject every invalid coordinate before
    // encoding or touching the packed destination.
    UE5M3[3] destination = [UE5M3.from_code(11), UE5M3.from_code(23),
                           UE5M3.from_code(37)];
    const before = destination;
    if (try_store_at(destination[], 3, Float16.from_float(1.0f))) return 1;
    if (try_store_at(destination[], size_t.max, Float16.from_float(1.0f))) return 2;
    if (destination != before) return 3;

    UE5M3[0] empty;
    if (try_store_at(empty[], 0, Float16.from_float(1.0f))) return 4;

    auto offset = destination[1 .. 3];
    const offsetBefore = offset;
    if (try_store_at(offset, 2, Float16.from_float(1.0f))) return 5;
    if (offset != offsetBefore) return 6;
    if (!try_store_at(offset, 1, Float16.from_float(2.0f))) return 7;
    if (destination[2].code() != oracle_encode(4, 0x40000000u)) return 8;
    return 0;
}
