#include <ick/circle.h>
#include <assert.h>
#include <stdint.h>

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

static Float16 oracle_float16_binary(unsigned operation, Float16 left, Float16 right)
{
    switch (operation) {
    case 0: return float16_add(left, right);
    case 1: return float16_subtract(left, right);
    case 2: return float16_multiply(left, right);
    case 3: return float16_divide(left, right);
    default: return float16_from_code(0);
    }
}

unsigned oracle_float16_chain(unsigned first_operation, unsigned second_operation,
                              unsigned left, unsigned middle, unsigned right)
{
    Float16 first = float16_from_code((ick_u16)left);
    Float16 second = float16_from_code((ick_u16)middle);
    Float16 third = float16_from_code((ick_u16)right);
    Float16 rounded_intermediate =
        oracle_float16_binary(first_operation, first, second);
    return float16_code(
        oracle_float16_binary(second_operation, rounded_intermediate, third));
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

/* Independent signed nine-bit E5M3 arithmetic oracle.
 *
 * Work in integer units of 2^-17.  Quantization binary-searches the ordered
 * set of finite output codes, comparing twice the result against adjacent
 * integer-code sums.  No float, Float16, or D quantizer is used.
 */
static int oracle_signed_e5m3_is_nan(unsigned code)
{
    return (code & 0xf8u) == 0xf8u && (code & 7u) != 0;
}

static int oracle_signed_e5m3_is_inf(unsigned code)
{
    return (code & 0xffu) == 0xf8u;
}

static int64_t oracle_signed_e5m3_positive_units(unsigned code)
{
    unsigned exponent = (code >> 3) & 31u;
    unsigned fraction = code & 7u;
    assert(exponent != 31u);
    if (exponent == 0) return (int64_t)fraction;
    return (int64_t)(8u + fraction) << (exponent - 1u);
}

static int64_t oracle_signed_e5m3_units(unsigned code)
{
    int64_t magnitude = oracle_signed_e5m3_positive_units(code);
    return (code & 0x100u) ? -magnitude : magnitude;
}

static unsigned oracle_signed_e5m3_round(int64_t result)
{
    int negative = result < 0;
    uint64_t magnitude = (uint64_t)(negative ? -result : result);
    unsigned low = 0, high = 248;
    while (low < high)
    {
        unsigned middle = low + (high - low) / 2;
        uint64_t lower = (uint64_t)oracle_signed_e5m3_positive_units(middle);
        /* Code 248 is infinity. Its conceptual even successor at 65536
         * gives the finite/infinity midpoint 63488. */
        uint64_t upper = middle == 247u
            ? ((uint64_t)65536u << 17)
            : (uint64_t)oracle_signed_e5m3_positive_units(middle + 1u);
        uint64_t twice = 2u * magnitude;
        uint64_t boundary = lower + upper;
        if (twice < boundary || (twice == boundary && (middle & 1u) == 0))
            high = middle;
        else
            low = middle + 1;
    }
    return (negative ? 0x100u : 0u) | low;
}

unsigned oracle_signed_e5m3_operation(unsigned operation,
                                     unsigned left, unsigned right)
{
    if (operation > 1u) return 0x10000u;
    left &= 0x1ffu;
    right &= 0x1ffu;
    if (operation == 1u) right ^= 0x100u;

    if (oracle_signed_e5m3_is_nan(left) || oracle_signed_e5m3_is_nan(right))
        return 0xfcu;

    int left_inf = oracle_signed_e5m3_is_inf(left);
    int right_inf = oracle_signed_e5m3_is_inf(right);
    if (left_inf || right_inf)
    {
        if (left_inf && right_inf && ((left ^ right) & 0x100u))
            return 0xfcu;
        return left_inf ? left : right;
    }

    /* Under round-to-nearest/even, same-signed zero preserves its sign;
     * other exact cancellation has positive zero. */
    if ((left & 0xffu) == 0 && (right & 0xffu) == 0)
        return (left & right & 0x100u) ? 0x100u : 0u;

    int64_t sum = oracle_signed_e5m3_units(left)
                + oracle_signed_e5m3_units(right);
    if (sum == 0) return 0;
    return oracle_signed_e5m3_round(sum);
}

unsigned oracle_signed_e5m3_compare(unsigned predicate,
                                   unsigned left, unsigned right)
{
    if (predicate > 1u) return 0x10000u;
    left &= 0x1ffu;
    right &= 0x1ffu;
    if (oracle_signed_e5m3_is_nan(left) || oracle_signed_e5m3_is_nan(right))
        return 0u;

    int left_inf = oracle_signed_e5m3_is_inf(left);
    int right_inf = oracle_signed_e5m3_is_inf(right);
    if (predicate == 0u)
    {
        if (left_inf || right_inf)
            return left_inf && right_inf && left == right;
        return oracle_signed_e5m3_units(left) == oracle_signed_e5m3_units(right);
    }
    if (left_inf && right_inf)
        return (left & 0x100u) != 0 && (right & 0x100u) == 0;
    if (left_inf) return (left & 0x100u) != 0;
    if (right_inf) return (right & 0x100u) == 0;
    return oracle_signed_e5m3_units(left) < oracle_signed_e5m3_units(right);
}
