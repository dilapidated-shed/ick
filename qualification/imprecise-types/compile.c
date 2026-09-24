#include <stdint.h>
#include <ick/imprecise.h>

_Static_assert(sizeof(E3M2) == 1, "E3M2 must occupy one byte in C objects");
_Static_assert(sizeof(E5M3) == 1, "E5M3 must occupy one byte in C objects");

uint8_t
ick_e3m2_round_trip_code(uint8_t code)
{
    return e3m2_code(e3m2_from_float(e3m2_to_float(e3m2_from_code(code))));
}

int
ick_e5m3_round_trip_code(uint8_t code, uint8_t *round_tripped)
{
    E5M3 encoded = e5m3_from_code(code);
    E5M3 result;
    if (!e5m3_from_float(e5m3_to_float(encoded), &result))
        return 0;
    *round_tripped = e5m3_code(result);
    return 1;
}
