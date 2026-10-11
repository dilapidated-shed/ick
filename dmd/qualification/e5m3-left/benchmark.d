module benchmark;
import icky.imprecise : E5M3, Float16;
import icky.experimental.e5m3_left;
import core.stdc.stdlib : malloc, free;
import core.stdc.stdio : printf;
import core.sys.posix.time : timespec, clock_gettime, CLOCK_MONOTONIC;
nothrow @nogc:

struct RightE5M3
{
    nothrow @nogc:
    E5M3 value;
    static RightE5M3 from_code(ushort code)
    {
        RightE5M3 result; result.value = E5M3.from_code(code); return result;
    }
    ushort code() const { return value.code(); }
    ushort storage() const { return code(); }
    Float16 widen() const { return Float16.from_code(cast(ushort)(code() << 7)); }
    static RightE5M3 narrow(Float16 half)
    {
        return from_code(narrow_half_to_right(half).code());
    }
    RightE5M3 opBinary(string op)(RightE5M3 other) const if(op == "+")
    {
        return from_code((value + other.value).code());
    }
}

ulong now()
{
    timespec stamp;
    assert(clock_gettime(CLOCK_MONOTONIC, &stamp) == 0);
    return cast(ulong)stamp.tv_sec * 1_000_000_000u + stamp.tv_nsec;
}

// Separate instantiations permit inspection of layout-specific instructions.
pragma(inline, false)
ulong kernel(T, uint mode)(T* input, T* output, uint length)
{
    ulong checksum;
    foreach (uint index; 0 .. length)
    {
        auto a = input[index];
        static if (mode == 0) checksum += a.storage();
        else static if (mode == 1) checksum += a.widen().code();
        else static if (mode == 2)
            checksum += (a + input[(index + 1) % length]).storage();
        else static if (mode == 3)
        {
            // Defined 32 additions, always requantized, including overflow.
            auto increment = T.from_code(1);
            foreach (uint iteration; 0 .. 32u) a = a + increment;
            output[index] = a; checksum += a.storage();
        }
        else static if (mode == 4)
        {
            auto half = a.widen() * input[(index + 1) % length].widen();
            auto product = T.narrow(half);
            output[index] = product; checksum += product.storage();
        }
        else
        {
            auto converted = T.narrow(a.widen());
            output[index] = converted; checksum += converted.storage();
        }
    }
    return checksum;
}

void measure(T, uint mode)(const(char)* name, uint length, uint sample)
{
    auto input = cast(T*)malloc(length * T.sizeof);
    auto output = cast(T*)malloc(length * T.sizeof);
    assert(input !is null && output !is null);
    foreach (uint index; 0 .. length)
        input[index] = T.from_code(cast(ushort)(1u + ((index * 37u) % 240u)));
    auto expected = kernel!(T, mode)(input, output, length); // warm, consume stores
    ulong begin = now();
    auto observed = kernel!(T, mode)(input, output, length);
    ulong elapsed = now() - begin;
    assert(observed == expected);
    static if (mode != 0 && mode != 1 && mode != 2)
    {
        ulong stored;
        foreach (uint index; 0 .. length) stored += output[index].storage();
        assert(stored == observed);
    }
    static if (is(T == LeftE5M3) && mode != 1) observed >>= 7;
    printf("%s\t%u\t%u\t%u\t%llu\t%llu\n", name, mode, length,
           sample, elapsed, observed);
    free(output); free(input);
}

extern(C) int main()
{
    printf("layout\tkernel\telements\tsample\tnanoseconds\tlogical_checksum\n");
    foreach (uint length; [256u, 16384u, 1048576u])
        foreach (uint sample; 0 .. 7u)
            static foreach (uint mode; 0 .. 6u)
            {
                // Alternate order to limit systematic thermal/order bias.
                if (sample & 1u)
                {
                    measure!(LeftE5M3, mode)("left", length, sample);
                    measure!(RightE5M3, mode)("right", length, sample);
                }
                else
                {
                    measure!(RightE5M3, mode)("right", length, sample);
                    measure!(LeftE5M3, mode)("left", length, sample);
                }
            }
    // 64 MiB input exceeds the observed host's 32 MiB L3. Output-bearing
    // kernels have a 128 MiB working set. The 32-add kernel is separately
    // measured above; this tier isolates memory pressure in streaming paths.
    foreach (uint sample; 0 .. 3u)
        static foreach (uint mode; [0u, 1u, 2u, 4u, 5u])
        {
            if (sample & 1u)
            {
                measure!(LeftE5M3, mode)("left", 33554432u, sample);
                measure!(RightE5M3, mode)("right", 33554432u, sample);
            }
            else
            {
                measure!(RightE5M3, mode)("right", 33554432u, sample);
                measure!(LeftE5M3, mode)("left", 33554432u, sample);
            }
        }
    return 0;
}
