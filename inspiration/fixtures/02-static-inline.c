/*
 * Reduction for:
 *   Linux mm/memfd.c:is_write_sealed
 *   ICK circle.h:rotate96
 *
 * Keep C inline semantics separate from optimizer call substitution.
 */
typedef struct {
    unsigned char code;
} circle96_like;

static inline int
flag_is_set(unsigned int flags)
{
    return flags & 0x30u;
}

static inline circle96_like
rotate96_like(circle96_like amount, circle96_like point)
{
    unsigned int sum = (unsigned int)amount.code + point.code;
    circle96_like result;

    if (sum >= 96u)
        sum -= 96u;

    result.code = (unsigned char)sum;
    return result;
}

unsigned int
use_inline_pair(unsigned int flags, unsigned char a, unsigned char b)
{
    circle96_like left = { a };
    circle96_like right = { b };
    circle96_like rotated = rotate96_like(left, right);

    return (unsigned int)rotated.code + (unsigned int)flag_is_set(flags);
}
