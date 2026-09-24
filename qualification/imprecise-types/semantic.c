#include <stdint.h>
#include <ick/imprecise.h>

static int
expect_e3(uint32_t bits, uint8_t code)
{
    return e3m2_code(e3m2_from_float(ick_float_from_bits(bits))) == code;
}

int
main(void)
{
    E5M3 e5 = e5m3_from_code(77);
    unsigned code;

    for (code = 0; code < 64; ++code)
        if (e3m2_code(e3m2_from_float(e3m2_to_float(e3m2_from_code(code)))) != code)
            return 1;

    if (!expect_e3(0x3d000000u, 0)       /* 0.03125: tie -> even zero. */
        || !expect_e3(0x3dc00000u, 2)    /* 0.09375: tie -> even code 2. */
        || !expect_e3(0x3e200000u, 2)    /* 0.15625: tie -> even code 2. */
        || !expect_e3(0x3e600000u, 4)    /* 0.21875: tie -> even code 4. */
        || !expect_e3(0x41d00000u, 30))  /* 26: tie -> 24, code 30. */
        return 2;

    if (e3m2_code(e3m2_from_float(1000.0f)) != 31
        || e3m2_code(e3m2_from_float(-1000.0f)) != 63)
        return 3;

    if (e3m2_code(e3m2_from_float(ick_float_from_bits(0x7fc00000u))) != 0
        || e3m2_code(e3m2_from_float(ick_float_from_bits(0xffc00000u))) != 32)
        return 4;

    if (ick_float_bits(e3m2_to_float(e3m2_from_code(32))) != 0x80000000u)
        return 5;

    for (code = 0; code < 256; ++code) {
        E5M3 original = e5m3_from_code((uint8_t)code);
        E5M3 round_tripped;
        if (!e5m3_from_float(e5m3_to_float(original), &round_tripped)
            || e5m3_code(round_tripped) != code)
            return 6;
    }

    if (e5m3_from_float(-1.0f, &e5)
        || e5m3_from_float(0.0f, &e5)
        || e5m3_from_float(ick_float_from_bits(0x7f800000u), &e5)
        || e5m3_from_float(ick_float_from_bits(0x7fc00000u), &e5)
        || e5m3_code(e5) != 77)
        return 7;

    return 0;
}
