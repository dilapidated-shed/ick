#include <ick/imprecise.h>
#include <ick/circle.h>

static int
is_nan(float value)
{
    return value != value;
}

int
main(void)
{
    unsigned code;

    for (code = 0; code < 65536; ++code) {
        Float16 value = float16_from_code((ick_u16)code);
        float decoded = float16_to_float(value);
        ick_u16 exponent = ((ick_u16)code >> 10) & 31u;
        ick_u16 mantissa = (ick_u16)code & 1023u;

        if (exponent == 31u && mantissa != 0) {
            if (!is_nan(decoded))
                return 1;
        } else if (float16_code(float16_from_float(decoded)) != (ick_u16)code) {
            return 2;
        }
    }

    if (float16_code(float16_from_float(65519.0f)) != 0x7bffu)
        return 3;
    if (float16_code(float16_from_float(65520.0f)) != 0x7c00u)
        return 4;
    if (float16_code(float16_from_float(ick_float_from_bits(0x33000000u))) != 0u)
        return 5;

    for (code = 0; code <= 0x7e; ++code) {
        E4M3 value = e4m3_from_code((ick_byte)code);
        if (e4m3_code(e4m3_from_float(e4m3_to_float(value))) != code)
            return 10;
    }
    if (e4m3_code(e4m3_from_float(448.0f)) != 0x7eu)
        return 11;
    if (!is_nan(e4m3_to_float(e4m3_from_code(0x7fu))))
        return 12;

    for (code = 0; code <= 0x7b; ++code) {
        E5M2 value = e5m2_from_code((ick_byte)code);
        if (e5m2_code(e5m2_from_float(e5m2_to_float(value))) != code)
            return 20;
    }
    if (e5m2_code(e5m2_from_float(ick_float_from_bits(0x7f800000u))) != 0x7bu)
        return 21;
    if (!is_nan(e5m2_to_float(e5m2_from_code(0x7fu))))
        return 22;

    for (code = 0; code < 64; ++code) {
        E3M2 value = e3m2_from_code((ick_byte)code);
        if (e3m2_code(e3m2_from_float(e3m2_to_float(value))) != code)
            return 30;
    }
    if (e3m2_code(e3m2_from_float(1000.0f)) != 31)
        return 31;
    if (e3m2_code(e3m2_from_float(-1000.0f)) != 63)
        return 32;

    for (code = 0; code < 256; ++code) {
        E5M3 value = e5m3_from_code((ick_byte)code);
        E5M3 round_tripped;
        if (!e5m3_from_float(e5m3_to_float(value), &round_tripped)
            || e5m3_code(round_tripped) != code)
            return 40;
    }

    if (e3m2_code(e3m2_add(e3m2_from_float(16.0f), e3m2_from_float(16.0f))) != 31)
        return 41;
    if (e4m3_code(e4m3_add(e4m3_from_float(256.0f), e4m3_from_float(256.0f))) != 0x7eu)
        return 42;
    if (e5m2_code(e5m2_add(e5m2_from_float(32768.0f), e5m2_from_float(32768.0f))) != 0x7bu)
        return 43;
    if (float16_code(float16_add(float16_from_float(65504.0f), float16_from_float(65504.0f))) != 0x7c00u)
        return 44;

    if (third_sector(circle96(32)) != 1
        || third_sector(circle96(64)) != 2)
        return 50;
    if (position_within_third(circle96(16)) != 16)
        return 51;
    if (circle96_code(rotate96(one_flat96(), circle96(88))) != 8)
        return 52;
    if (circle96_code(rotate96(inverse_rotation96(one_flat96()),
                               rotate96(one_flat96(), circle96(23)))) != 23)
        return 53;
    if (circle96_code(reflect96(reflection96(17),
                                reflect96(reflection96(17), circle96(31)))) != 31)
        return 54;
    if (tangent96_ticks(local_displacement96(circle96(1), circle96(95))) != 2)
        return 55;
    if (tangent96_ticks(local_displacement96(circle96(95), circle96(1))) != -2)
        return 56;
    if (tangent96_ticks(local_displacement96(circle96(48), circle96(0))) != -48)
        return 57;

    {
        Circle96 value;
        if (!circle96_from_code(95, &value) || circle96_from_code(96, &value))
            return 58;
    }

    return 0;
}
