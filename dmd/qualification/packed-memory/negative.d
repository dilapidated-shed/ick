module packed_memory_negative;

import icky.imprecise;
import icky.packed_memory;

E5M3[1] e5;
E3M2[1] e3;
E4M3[1] e4;
ubyte[1] bytes;
const(E5M3)[1] read_only;
E5M3 direct_output;

void accepts_widened_slice(Float16[] value) {}

static assert(!__traits(compiles,
    icky.packed_memory.compute_at!(E3M2, "+")(e5[], 0, e5[], 0)));
static assert(!__traits(compiles,
    icky.packed_memory.compute_at!(Float16, "%")(e5[], 0, e5[], 0)));
static assert(!__traits(compiles,
    icky.packed_memory.compute_at!(Float16, "+")(bytes[], 0, e5[], 0)));
static assert(!__traits(compiles,
    icky.packed_memory.compute_at!(Float16, "+")(e4[], 0, e5[], 0)));
static assert(!__traits(compiles,
    icky.packed_memory.compute_at!(Float16, "+")(e5[], 0, e5[], 0)));
static assert(!__traits(compiles,
    icky.packed_memory.compute_at!(Float16, "-")(e5[], 0, e5[], 0)));
static assert(__traits(compiles,
    icky.packed_memory.try_e5m3_at!("+")(e5[], 0, e5[], 0, direct_output)));
static assert(__traits(compiles,
    icky.packed_memory.try_e5m3_at!("-")(e5[], 0, e5[], 0, direct_output)));
static assert(__traits(compiles,
    icky.packed_memory.try_e5m3_at!("*")(e5[], 0, e5[], 0, direct_output)));
static assert(!__traits(compiles,
    icky.packed_memory.try_e5m3_at!("/")(e5[], 0, e5[], 0, direct_output)));
static assert(!__traits(compiles,
    icky.packed_memory.try_e5m3_at!("+")(e5[], 0, e3[], 0, direct_output)));
static assert(!__traits(compiles, e5[0] + e5[0]));
static assert(!__traits(compiles,
    icky.packed_memory.try_store_at(read_only[], 0, Float16.init)));
static assert(!__traits(compiles,
    accepts_widened_slice(e5[])));

// The compiler seam is module-qualified.  A similarly named user function
// remains ordinary D behavior.
int packed_read(int value) { return value + 1; }
int packed_write(int value) { return value + 2; }
int compute_at(int value) { return value + 3; }
int try_store_at(int value) { return value + 4; }

static assert(__traits(compiles, packed_read(1)));
static assert(__traits(compiles, packed_write(1)));
static assert(__traits(compiles, compute_at(1)));
static assert(__traits(compiles, try_store_at(1)));

extern(C) int main()
{
    return packed_read(1) == 2 && packed_write(1) == 3 &&
           compute_at(1) == 4 && try_store_at(1) == 5 ? 0 : 1;
}
