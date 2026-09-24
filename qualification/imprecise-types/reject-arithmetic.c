#include <ick/imprecise.h>

#if defined(TEST_E3)
E3M2
bad_e3m2_add(E3M2 left, E3M2 right)
{
    return left + right;
}
#elif defined(TEST_E5)
E5M3
bad_e5m3_multiply(E5M3 left, E5M3 right)
{
    return left * right;
}
#else
#error define TEST_E3 or TEST_E5
#endif
