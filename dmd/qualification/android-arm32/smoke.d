module android_arm32_a32;

version (Android) {} else static assert(0, "Android version must be predefined");
version (ARM) {} else static assert(0, "ARM version must be predefined");
version (ARM_SoftFP) {} else static assert(0, "ARM_SoftFP version must be predefined");
version (CRuntime_Bionic) {} else static assert(0, "Bionic C runtime must be selected");

static assert(size_t.sizeof == 4);
static assert(real.sizeof == 8);

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
