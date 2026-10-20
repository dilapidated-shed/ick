#include <ick/imprecise.h>
#include <ick/circle.h>

static int
is_nan(float value)
{
    return value != value;
}

/* Deliberately independent of the production byte-to-Float32 decoder:
   evaluate the signed exponent/significand formula directly.  Every finite
   FP8 value fits exactly in binary32, including negative zero and subnormals. */
static float
reference_power_of_two(int exponent)
{
    float factor = 1.0f;
    while (exponent > 0) {
        factor *= 2.0f;
        --exponent;
    }
    while (exponent < 0) {
        factor *= 0.5f;
        ++exponent;
    }
    return factor;
}

static float
reference_fp8_finite(unsigned code, unsigned exponent_bits,
                     unsigned mantissa_bits, int bias)
{
    unsigned mantissa_mask = (1u << mantissa_bits) - 1u;
    unsigned exponent_mask = (1u << exponent_bits) - 1u;
    unsigned exponent = (code >> mantissa_bits) & exponent_mask;
    unsigned mantissa = code & mantissa_mask;
    float value;
    if (exponent == 0)
        value = (float)mantissa
            * reference_power_of_two(1 - bias - (int)mantissa_bits);
    else
        value = (float)((1u << mantissa_bits) + mantissa)
            * reference_power_of_two((int)exponent - bias - (int)mantissa_bits);
    return (code & 0x80u) ? -value : value;
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

    /* Standard signed OCP FP8: these identities catch format swaps. */
    if (e4m3_code(e4m3_from_float(1.0f)) != 0x38u
        || e4m3_code(e4m3_from_float(-1.0f)) != 0xb8u
        || e5m2_code(e5m2_from_float(1.0f)) != 0x3cu
        || e5m2_code(e5m2_from_float(-1.0f)) != 0xbcu)
        return 60;
    if (e4m3_code(e4m3_from_float(1.0f / 512.0f)) != 0x01u
        || e4m3_code(e4m3_from_float(1.0f / 64.0f)) != 0x08u
        || e5m2_code(e5m2_from_float(1.0f / 65536.0f)) != 0x01u
        || e5m2_code(e5m2_from_float(1.0f / 16384.0f)) != 0x04u)
        return 61;
    if (e4m3_code(e4m3_from_float(1.0625f)) != 0x38u
        || e4m3_code(e4m3_from_float(1.1875f)) != 0x3au
        || e5m2_code(e5m2_from_float(1.125f)) != 0x3cu
        || e5m2_code(e5m2_from_float(1.375f)) != 0x3eu)
        return 62;
    if (e4m3_code(e4m3_from_float(ick_float_from_bits(0x7f800000u))) != 0x7eu
        || e4m3_code(e4m3_from_float(ick_float_from_bits(0xff800000u))) != 0xfeu
        || e5m2_code(e5m2_from_float(ick_float_from_bits(0x7f800000u))) != 0x7bu
        || e5m2_code(e5m2_from_float(ick_float_from_bits(0xff800000u))) != 0xfbu)
        return 63;
    if (e4m3_to_float(e4m3_from_code(0x7eu)) != 448.0f
        || e5m2_to_float(e5m2_from_code(0x7bu)) != 57344.0f
        || !is_nan(e4m3_to_float(e4m3_from_code(0xffu)))
        || !is_nan(e5m2_to_float(e5m2_from_code(0x7du))))
        return 64;

    /* All 256 signed payloads, including negative finite, signed zeros,
       subnormals, infinities and NaNs.  Saturating E5M2 construction
       sends infinity to signed maximum finite rather than its original
       raw infinity code. */
    for (code = 0; code < 256; ++code) {
        float decoded_e4 = e4m3_to_float(e4m3_from_code((ick_byte)code));
        float decoded_e5 = e5m2_to_float(e5m2_from_code((ick_byte)code));

        /* Decode against the mathematical 1/4/3 and 1/5/2 definitions,
           not against the same codec's own re-encoder.  Compare binary32
           bits to retain the sign of zero. */
        if ((code & 0x7fu) != 0x7fu
            && ick_float_bits(decoded_e4)
               != ick_float_bits(reference_fp8_finite(code, 4u, 3u, 7)))
            return 70;
        if ((code & 0x7cu) != 0x7cu
            && ick_float_bits(decoded_e5)
               != ick_float_bits(reference_fp8_finite(code, 5u, 2u, 15)))
            return 71;
        if ((code & 0x7fu) == 0x7cu
            && ick_float_bits(decoded_e5)
               != ((code & 0x80u) ? 0xff800000u : 0x7f800000u))
            return 72;

        if ((code & 0x7fu) == 0x7fu) {
            if (!is_nan(decoded_e4))
                return 65;
        } else if (e4m3_code(e4m3_from_float(decoded_e4)) != code) {
            return 66;
        }

        if ((code & 0x7cu) == 0x7cu && (code & 0x03u) != 0u) {
            if (!is_nan(decoded_e5))
                return 67;
        } else if ((code & 0x7fu) == 0x7cu) {
            if (e5m2_code(e5m2_from_float(decoded_e5))
                != (ick_byte)((code & 0x80u) ? 0xfbu : 0x7bu))
                return 68;
        } else if (e5m2_code(e5m2_from_float(decoded_e5)) != code) {
            return 69;
        }
    }

    for (code = 0; code < 64; ++code) {
        E3M2 value = e3m2_from_code((ick_byte)code);
        if (e3m2_code(e3m2_from_float(e3m2_to_float(value))) != code)
            return 30;
    }
    if (e3m2_code(e3m2_from_float(1000.0f)) != 31)
        return 31;
    if (e3m2_code(e3m2_from_float(-1000.0f)) != 63)
        return 32;
    if (e3m2_code(e3m2_from_float(ick_float_from_bits(0x7fc00000u))) != 0
        || e3m2_code(e3m2_from_float(ick_float_from_bits(0xffc00000u))) != 0)
        return 33;

    for (code = 0; code < 256; ++code) {
        OotomoE5M3 value = ootomo_e5m3_from_code((ick_byte)code);
        OotomoE5M3 round_tripped;
        if (!ootomo_e5m3_from_float(ootomo_e5m3_to_float(value), &round_tripped)
            || ootomo_e5m3_code(round_tripped) != code)
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
