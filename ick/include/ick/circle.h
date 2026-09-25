#ifndef ICK_CIRCLE_H
#define ICK_CIRCLE_H

#include <ick/imprecise.h>

_Static_assert(__SCHAR_MAX__ >= 127, "Circle96 tangent needs signed 8-bit range");

typedef struct { ick_byte code; } Circle96;
typedef struct { ick_byte code; } Rotation96;
typedef struct { ick_byte code; } Reflection96;
typedef struct { signed char ticks; } Tangent96;

_Static_assert(sizeof(Circle96) == 1, "Circle96 storage must be one byte");
_Static_assert(sizeof(Rotation96) == 1, "Rotation96 storage must be one byte");
_Static_assert(sizeof(Reflection96) == 1, "Reflection96 storage must be one byte");
_Static_assert(sizeof(Tangent96) == 1, "Tangent96 storage must be one byte");

static inline int
circle96_code_is_canonical(ick_byte code)
{
    return code < 96u;
}

static inline ick_byte
circle96_normalize(int value)
{
    int remainder = value % 96;
    if (remainder < 0)
        remainder += 96;
    return (ick_byte)remainder;
}

static inline Circle96
circle96(int value)
{
    Circle96 result = { circle96_normalize(value) };
    return result;
}

static inline Rotation96
rotation96(int value)
{
    Rotation96 result = { circle96_normalize(value) };
    return result;
}

static inline Reflection96
reflection96(int value)
{
    Reflection96 result = { circle96_normalize(value) };
    return result;
}

static inline int
circle96_from_code(ick_byte code, Circle96 *out)
{
    if (!out || !circle96_code_is_canonical(code))
        return 0;
    out->code = code;
    return 1;
}

static inline int
rotation96_from_code(ick_byte code, Rotation96 *out)
{
    if (!out || !circle96_code_is_canonical(code))
        return 0;
    out->code = code;
    return 1;
}

static inline int
reflection96_from_code(ick_byte code, Reflection96 *out)
{
    if (!out || !circle96_code_is_canonical(code))
        return 0;
    out->code = code;
    return 1;
}

static inline ick_byte circle96_code(Circle96 value) { return value.code; }
static inline ick_byte rotation96_code(Rotation96 value) { return value.code; }
static inline ick_byte reflection96_code(Reflection96 value) { return value.code; }
static inline int tangent96_ticks(Tangent96 value) { return value.ticks; }

static inline ick_byte
third_sector(Circle96 value)
{
    return value.code >> 5;
}

static inline ick_byte
position_within_third(Circle96 value)
{
    return value.code & 31u;
}

static inline Circle96
rotate96(Rotation96 amount, Circle96 point)
{
    unsigned sum = (unsigned)amount.code + point.code;
    if (sum >= 96u)
        sum -= 96u;
    return circle96((int)sum);
}

static inline Rotation96
compose_rotations96(Rotation96 first, Rotation96 second)
{
    unsigned sum = (unsigned)first.code + second.code;
    if (sum >= 96u)
        sum -= 96u;
    return rotation96((int)sum);
}

static inline Rotation96
inverse_rotation96(Rotation96 amount)
{
    return rotation96(amount.code == 0 ? 0 : 96 - amount.code);
}

static inline Circle96
reflect96(Reflection96 reflection, Circle96 point)
{
    int result = (int)reflection.code - (int)point.code;
    if (result < 0)
        result += 96;
    return circle96(result);
}

static inline Tangent96
local_displacement96(Circle96 to, Circle96 from)
{
    int displacement = (int)to.code - (int)from.code;
    if (displacement >= 48)
        displacement -= 96;
    if (displacement < -48)
        displacement += 96;
    {
        Tangent96 result = { (signed char)displacement };
        return result;
    }
}

static inline Rotation96 one_third_turn96(void) { return rotation96(32); }
static inline Rotation96 two_thirds_turn96(void) { return rotation96(64); }
static inline Rotation96 one_flat96(void) { return rotation96(16); }
static inline Rotation96 half_flat96(void) { return rotation96(8); }
static inline Rotation96 quarter_flat96(void) { return rotation96(4); }
static inline Rotation96 eighth_flat96(void) { return rotation96(2); }
static inline Rotation96 sixteenth_flat96(void) { return rotation96(1); }

#endif
