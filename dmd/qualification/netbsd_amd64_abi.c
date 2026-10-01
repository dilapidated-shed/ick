#include <stddef.h>
#include <stdint.h>

struct netbsd_mixed {
    double scale;
    long count;
};

struct netbsd_large {
    long first;
    long second;
    long third;
};

extern int netbsd_add(int, int);
extern long netbsd_wide(long, long);
extern double netbsd_mix(int, double, double);
extern unsigned long netbsd_pointer_sum(const int *, unsigned long);
extern struct netbsd_mixed netbsd_mixed(struct netbsd_mixed, double, long);
extern long netbsd_vararg_sum(int, ...);
extern long netbsd_many_ints(long, long, long, long, long, long, long, long);
extern double netbsd_many_fp(double, double, double, double, double,
    double, double, double, double, double);
extern long double netbsd_long_double(long double);
extern struct netbsd_large netbsd_large(struct netbsd_large, long);
extern double netbsd_vararg_mixed(int, ...);
extern int netbsd_callback(int (*)(int), int);
extern int netbsd_tls_bump(void);

_Static_assert(sizeof(int) == 4, "NetBSD/amd64 int must be 32 bits");
_Static_assert(sizeof(long) == 8, "NetBSD/amd64 long must be 64 bits");
_Static_assert(sizeof(void *) == 8, "NetBSD/amd64 pointers must be 64 bits");
_Static_assert(sizeof(double) == 8, "NetBSD/amd64 double must be 64 bits");
_Static_assert(sizeof(struct netbsd_mixed) == 16,
    "mixed aggregate must occupy two eight-byte ABI classes");
_Static_assert(offsetof(struct netbsd_mixed, scale) == 0,
    "mixed aggregate double offset mismatch");
_Static_assert(offsetof(struct netbsd_mixed, count) == 8,
    "mixed aggregate integer offset mismatch");
_Static_assert(sizeof(struct netbsd_large) == 24,
    "large aggregate must use the SysV memory class");
_Static_assert(sizeof(long double) == 16,
    "NetBSD/amd64 long double storage must be 16 bytes");

static int
plus_ten(int value)
{
    return value + 10;
}

int
main(void)
{
    const int values[] = {1, 2, 3, 4};
    struct netbsd_mixed mixed = {1.5, 7};
    struct netbsd_large large = {1, 2, 3};

    if (netbsd_add(20, 22) != 42)
        return 1;
    if (netbsd_wide(20, 7) != 53)
        return 2;
    if (netbsd_mix(2, 4.0, 8.0) != 6.0)
        return 3;
    if (netbsd_pointer_sum(values, 4) != 10)
        return 4;

    mixed = netbsd_mixed(mixed, 2.25, 5);
    if (mixed.scale != 3.75 || mixed.count != 12)
        return 5;

    if (netbsd_vararg_sum(4, 10L, 20L, 30L, 40L) != 100)
        return 6;

    if (netbsd_many_ints(1, 2, 3, 4, 5, 6, 7, 8) != 36)
        return 7;
    if (netbsd_many_fp(1.0, 2.0, 3.0, 4.0, 5.0,
            6.0, 7.0, 8.0, 9.0, 10.0) != 55.0)
        return 8;
    if (netbsd_long_double(1.25L) != 1.75L)
        return 9;

    large = netbsd_large(large, 4);
    if (large.first != 5 || large.second != 10 || large.third != 15)
        return 10;

    if (netbsd_vararg_mixed(10,
            1L, 1.5, 2L, 2.5, 3L, 3.5, 4L, 4.5, 5L, 5.5,
            6L, 6.5, 7L, 7.5, 8L, 8.5, 9L, 9.5, 10L, 10.5) != 115.0)
        return 11;

    if (netbsd_callback(plus_ten, 31) != 42)
        return 12;
    if (netbsd_tls_bump() != 1 || netbsd_tls_bump() != 2)
        return 13;

    return 0;
}
