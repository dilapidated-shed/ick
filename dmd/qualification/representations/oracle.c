#include <ick/circle.h>

/* This file deliberately calls the existing C implementation; it does not
   copy the D algorithms into a second, self-confirming implementation. */
unsigned oracle_decode(unsigned format, unsigned code)
{
    switch (format) {
    case 0: return ick_float_bits(float16_to_float(float16_from_code((ick_u16)code)));
    case 1: return ick_float_bits(e4m3_to_float(e4m3_from_code((ick_byte)code)));
    case 2: return ick_float_bits(e5m2_to_float(e5m2_from_code((ick_byte)code)));
    case 3: return ick_float_bits(e3m2_to_float(e3m2_from_code((ick_byte)code)));
    case 4: return ick_float_bits(e5m3_to_float(e5m3_from_code((ick_byte)code)));
    default: return 0;
    }
}

unsigned oracle_encode(unsigned format, unsigned bits)
{
    float value = ick_float_from_bits(bits);
    switch (format) {
    case 0: return float16_code(float16_from_float(value));
    case 1: return e4m3_code(e4m3_from_float(value));
    case 2: return e5m2_code(e5m2_from_float(value));
    case 3: return e3m2_code(e3m2_from_float(value));
    case 4: {
        E5M3 out = e5m3_from_code(0);
        return e5m3_from_float(value, &out) ? e5m3_code(out) : 0x10000u;
    }
    default: return 0x10000u;
    }
}

#define OPS(prefix, type) do { \
    type a = prefix##_from_code((ick_u16)left); \
    type b = prefix##_from_code((ick_u16)right); \
    switch (operation) { \
    case 0: return prefix##_code(prefix##_add(a, b)); \
    case 1: return prefix##_code(prefix##_subtract(a, b)); \
    case 2: return prefix##_code(prefix##_multiply(a, b)); \
    case 3: return prefix##_code(prefix##_divide(a, b)); \
    } \
} while (0)

unsigned oracle_operation(unsigned format, unsigned operation, unsigned left, unsigned right)
{
    switch (format) {
    case 0: OPS(float16, Float16); break;
    case 1: OPS(e4m3, E4M3); break;
    case 2: OPS(e5m2, E5M2); break;
    case 3: OPS(e3m2, E3M2); break;
    }
    return 0x10000u;
}

static float oracle_packed_decode(unsigned format, unsigned code)
{
    switch (format) {
    case 3: return e3m2_to_float(e3m2_from_code((ick_byte)code));
    case 4: return e5m3_to_float(e5m3_from_code((ick_byte)code));
    default: return 0.0f;
    }
}

/* Independent packed-memory oracle:
 * decode storage -> convert each operand to Float16 -> recover its binary32
 * semantic value -> perform one binary32 operation -> Float16 quantize.
 */
unsigned oracle_packed_operation(unsigned left_format, unsigned right_format,
                                 unsigned operation, unsigned left, unsigned right)
{
    Float16 left_half = float16_from_float(oracle_packed_decode(left_format, left));
    Float16 right_half = float16_from_float(oracle_packed_decode(right_format, right));
    volatile float left_value = float16_to_float(left_half);
    volatile float right_value = float16_to_float(right_half);
    float result;
    switch (operation) {
    case 0: result = left_value + right_value; break;
    case 1: result = left_value - right_value; break;
    case 2: result = left_value * right_value; break;
    case 3: result = left_value / right_value; break;
    default: return 0x10000u;
    }
    return float16_code(float16_from_float(result));
}

int oracle_circle(unsigned operation, int first, int second)
{
    switch (operation) {
    case 0: return circle96_code(rotate96(rotation96(first), circle96(second)));
    case 1: return circle96_code(reflect96(reflection96(first), circle96(second)));
    case 2: return tangent96_ticks(local_displacement96(circle96(first), circle96(second)));
    case 3: return rotation96_code(compose_rotations96(rotation96(first), rotation96(second)));
    case 4: return rotation96_code(inverse_rotation96(rotation96(first)));
    default: return -1000;
    }
}
