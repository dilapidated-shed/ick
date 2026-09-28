module android_arm_leaves;

version (Android) {} else static assert(0, "Android target missing");
version (CRuntime_Bionic) {} else static assert(0, "Bionic target missing");
version (X86) static assert(0, "Android ARM target advertised x86");
version (X86_64) static assert(0, "Android ARM target advertised x86_64");
version (ARM)
{
    static assert((void*).sizeof == 4);
    version (ARM_Thumb) {} else static assert(0);
    version (ARM_SoftFP) {} else static assert(0);
}
else version (AArch64) static assert((void*).sizeof == 8);
else static assert(0, "ARM target missing");

extern(C):

float calibrate(float gain, float sample, float bias)
{
    return gain × sample + bias;
}

float clamp_sample(float sample, float low, float high)
{
    if (sample < low) return low;
    if (sample > high) return high;
    return sample;
}

// A measured sample buffer, not a hard-coded constant-return smoke test.
float weighted_sum(const(float)* samples, uint count, float gain, float bias)
{
    float sum = bias;
    uint index = 0;
    while (index < count)
    {
        sum ← sum + gain × samples[index];
        index ← index + 1;
    }
    return sum;
}

void clip_buffer(float* samples, uint count, float low, float high)
{
    uint index = 0;
    while (index < count)
    {
        float sample = samples[index];
        if (sample < low) sample ← low;
        if (sample > high) sample ← high;
        samples[index] ← sample;
        index ← index + 1;
    }
}

uint comparison_mask(float x, float y)
{
    return cast(uint)(x < y) + 2 * cast(uint)(x <= y) +
           4 * cast(uint)(x ≟ y) + 8 * cast(uint)(x ≠ y) +
           16 * cast(uint)(x > y) + 32 * cast(uint)(x >= y);
}

int select_protocol(uint protocol, int fallback)
{
    if (protocol ≟ 6) return 1;
    if (protocol ≟ 17) return 2;
    if (protocol > 0x80000000U) return −7;
    return fallback;
}

int control_flow(int limit)
{
    int sum = 0;
    int i = 0;
    while (i < limit)
    {
        i = i + 1;
        if (i == 3) continue;
        if (i == 9) break;
        sum = sum + i;
    }
    return sum;
}

bool truth(float sample) { return cast(bool)sample; }
float divide(float numerator, float denominator) { return numerator ÷ denominator; }
float negate(float value) { return −value; }
