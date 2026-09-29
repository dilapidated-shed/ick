module netbsd_amd64_betterc;

import core.stdc.stdarg : va_arg, va_end, va_list, va_start;

version (NetBSD) {}
else static assert(0, "NetBSD target version was not defined");

version (Posix) {}
else static assert(0, "Posix target version was not defined");

version (X86_64) {}
else static assert(0, "X86_64 target version was not defined");

static assert(int.sizeof == 4);
static assert(long.sizeof == 8);
static assert(void*.sizeof == 8);
static assert(double.sizeof == 8);

struct NetbsdMixed
{
    double scale;
    long count;
}

extern(C) alias NetbsdCallback = int function(int);

private int tlsCounter;

extern(C) int netbsd_add(int a, int b)
{
    return a + b;
}

extern(C) long netbsd_wide(long a, long b)
{
    return a * 3 - b;
}

extern(C) double netbsd_mix(int tag, double x, double y)
{
    return cast(double) tag + x * 1.5 - y * 0.25;
}

extern(C) ulong netbsd_pointer_sum(const int* values, ulong count)
{
    long total;
    foreach (index; 0 .. count)
        total += values[index];
    return cast(ulong) total;
}

extern(C) NetbsdMixed netbsd_mixed(NetbsdMixed input, double delta, long extra)
{
    input.scale += delta;
    input.count += extra;
    return input;
}

extern(C) long netbsd_vararg_sum(int count, ...)
{
    va_list arguments;
    va_start(arguments, count);
    long total;
    foreach (_; 0 .. count)
        total += va_arg!long(arguments);
    va_end(arguments);
    return total;
}

extern(C) int netbsd_callback(NetbsdCallback callback, int value)
{
    return callback(value) + 1;
}

extern(C) int netbsd_tls_bump()
{
    return ++tlsCounter;
}
