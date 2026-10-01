module android_arm32_a32;

version (Android) {} else static assert(0, "Android version must be predefined");
version (ARM) {} else static assert(0, "ARM version must be predefined");
version (ARM_SoftFP) {} else static assert(0, "ARM_SoftFP version must be predefined");
version (CRuntime_Bionic) {} else static assert(0, "Bionic C runtime must be selected");

static assert(size_t.sizeof == 4);
static assert(real.sizeof == 8);

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
