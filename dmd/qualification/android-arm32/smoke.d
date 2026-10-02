module android_arm32_a32;

version (Android) {} else static assert(0, "Android version must be predefined");
version (ARM) {} else static assert(0, "ARM version must be predefined");
version (ARM_SoftFP) {} else static assert(0, "ARM_SoftFP version must be predefined");
version (CRuntime_Bionic) {} else static assert(0, "Bionic C runtime must be selected");

static assert(size_t.sizeof == 4);
static assert(real.sizeof == 8);
static assert(long.sizeof == 8);
static assert(double.sizeof == 8);

extern(C) int external_twice(int x);

extern(C) int add_int(int a, int b)
{
    return a + b;
}

extern(C) int sum5(int a, int b, int c, int d, int e)
{
    return a + b + c + d + e;
}

extern(C) float add_float(float a, float b)
{
    return a + b;
}

extern(C) float fifth_float(float a, float b, float c, float d, float e)
{
    return e;
}

extern(C) int choose(int x)
{
    if (x < 0)
        return -7;
    return x + 3;
}

extern(C) uint load_word(uint* p, uint i)
{
    return p[i];
}

extern(C) int call_internal(int x)
{
    return add_int(x, 9);
}

extern(C) int call_nested(int x)
{
    return add_int(add_int(x, 1), 2);
}

extern(C) int call_external(int x)
{
    return external_twice(x);
}

extern(C) int call_sum5(int x)
{
    return sum5(x, 2, 3, 4, 5);
}

extern(C) float call_float(float a, float b)
{
    return add_float(a, b);
}

extern(C) int signed_div(int a, int b)
{
    return a / b;
}

extern(C) uint unsigned_div(uint a, uint b)
{
    return a / b;
}

extern(C) int signed_mod(int a, int b)
{
    return a % b;
}

extern(C) uint unsigned_mod(uint a, uint b)
{
    return a % b;
}

extern(C) __gshared int own_global = 7;
extern(C) extern __gshared int external_global;

extern(C) int read_own_global()
{
    return own_global;
}

extern(C) int set_own_global(int x)
{
    own_global = x;
    return x;
}

extern(C) int read_external_global()
{
    return external_global;
}

extern(C) int set_external_global(int x)
{
    external_global = x;
    return x;
}

extern(C) int* own_global_address()
{
    return &own_global;
}

extern(C) long echo_long(long x)
{
    return x;
}

extern(C) double echo_double(double x)
{
    return x;
}

extern(C) long aligned_long(int a, long b, int c)
{
    return b;
}

extern(C) long stacked_long(int a, int b, int c, long d)
{
    return d;
}

extern(C) long call_aligned_long(long x)
{
    return aligned_long(1, x, 3);
}

extern(C) long call_stacked_long(long x)
{
    return stacked_long(1, 2, 3, x);
}

extern(C) double call_echo_double(double x)
{
    return echo_double(x);
}

extern(C) long long_constant()
{
    return 0x1122334455667788L;
}

extern(C) double double_constant()
{
    return 3.5;
}
