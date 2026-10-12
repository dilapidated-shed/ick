#include <ick/imprecise.h>
#include <ick/circle.h>

#if defined(TEST_OOTOMO_E5M3)
OotomoE5M3
bad_ootomo_e5m3_add(OotomoE5M3 left, OotomoE5M3 right)
{
    return left + right;
}
#elif defined(TEST_CIRCLE)
Circle96
bad_circle_add(Circle96 left, Circle96 right)
{
    return left + right;
}
#elif defined(TEST_CIRCLE_ROTATION_MIX)
Rotation96
bad_circle_rotation_mix(Circle96 point)
{
    return point;
}
#else
#error define TEST_OOTOMO_E5M3, TEST_CIRCLE, or TEST_CIRCLE_ROTATION_MIX
#endif
