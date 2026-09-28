module packed_memory_negative;

import icky.imprecise;
import icky.packed_memory;

E5M3[1] e5;
E3M2[1] e3;
E4M3[1] e4;
ubyte[1] bytes;
const(E5M3)[1] read_only;

void accepts_widened_slice(Float16[] value) {}

static assert(!__traits(compiles,
    compute_at!(E3M2, "+")(e5[], 0, e5[], 0)));
static assert(!__traits(compiles,
    compute_at!(Float16, "%")(e5[], 0, e5[], 0)));
static assert(!__traits(compiles,
    compute_at!(Float16, "+")(bytes[], 0, e5[], 0)));
static assert(!__traits(compiles,
    compute_at!(Float16, "+")(e4[], 0, e5[], 0)));
static assert(!__traits(compiles,
    try_store_at(read_only[], 0, Float16.init)));
static assert(!__traits(compiles,
    accepts_widened_slice(e5[])));

// The compiler seam is module-qualified.  A similarly named user function
// remains ordinary D behavior.
int packed_read(int value) { return value + 1; }
int packed_write(int value) { return value + 2; }

static assert(__traits(compiles, packed_read(1)));
static assert(__traits(compiles, packed_write(1)));

extern(C) int main()
{
    return packed_read(1) == 2 && packed_write(1) == 3 ? 0 : 1;
}
