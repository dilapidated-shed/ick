#include <ick/imprecise.h>
#include <ick/circle.h>

_Static_assert(sizeof(Float16) == 2, "Float16 must occupy two bytes");
_Static_assert(sizeof(E4M3) == 1, "E4M3 must occupy one byte");
_Static_assert(sizeof(E5M2) == 1, "E5M2 must occupy one byte");
_Static_assert(sizeof(E3M2) == 1, "E3M2 must occupy one byte");
_Static_assert(sizeof(E5M3) == 1, "E5M3 must occupy one byte");
_Static_assert(sizeof(Circle96) == 1, "Circle96 must occupy one byte");

ick_u16
ick_float16_round_trip_code(ick_u16 code)
{
    return float16_code(float16_from_float(float16_to_float(float16_from_code(code))));
}

ick_byte
ick_e4m3_round_trip_code(ick_byte code)
{
    return e4m3_code(e4m3_from_float(e4m3_to_float(e4m3_from_code(code))));
}

ick_byte
ick_e5m2_round_trip_code(ick_byte code)
{
    return e5m2_code(e5m2_from_float(e5m2_to_float(e5m2_from_code(code))));
}

ick_byte
ick_e3m2_round_trip_code(ick_byte code)
{
    return e3m2_code(e3m2_from_float(e3m2_to_float(e3m2_from_code(code))));
}

int
ick_e5m3_round_trip_code(ick_byte code, ick_byte *round_tripped)
{
    E5M3 encoded = e5m3_from_code(code);
    E5M3 result;
    if (!e5m3_from_float(e5m3_to_float(encoded), &result))
        return 0;
    *round_tripped = e5m3_code(result);
    return 1;
}

ick_byte
ick_e3m2_arithmetic(ick_byte left, ick_byte right)
{
    return e3m2_code(e3m2_add(e3m2_from_code(left), e3m2_from_code(right)));
}

ick_byte
ick_e4m3_arithmetic(ick_byte left, ick_byte right)
{
    return e4m3_code(e4m3_multiply(e4m3_from_code(left), e4m3_from_code(right)));
}

ick_byte
ick_e5m2_arithmetic(ick_byte left, ick_byte right)
{
    return e5m2_code(e5m2_subtract(e5m2_from_code(left), e5m2_from_code(right)));
}

ick_u16
ick_float16_arithmetic(ick_u16 left, ick_u16 right)
{
    return float16_code(float16_divide(float16_from_code(left), float16_from_code(right)));
}

int
ick_circle96_probe(int point, int amount)
{
    Circle96 moved = rotate96(rotation96(amount), circle96(point));
    return tangent96_ticks(local_displacement96(moved, circle96(point)));
}
