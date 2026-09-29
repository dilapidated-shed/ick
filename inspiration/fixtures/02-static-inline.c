/*
 * Separates C inline/linkage semantics from optimization-time call inlining.
 */
typedef struct {
    unsigned char payload;
} box8;

static inline box8
box8_xor(box8 value, unsigned char mask)
{
    value.payload ^= mask;
    return value;
}

unsigned char
use_box8_xor(unsigned char value, unsigned char mask)
{
    box8 wrapped = { value };
    return box8_xor(wrapped, mask).payload;
}
