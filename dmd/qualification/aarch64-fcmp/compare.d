module aarch64_fcmp_regression;

extern(C) uint comparison_mask(float x, float y)
{
    return cast(uint)(x < y)
         + 2u * cast(uint)(x <= y)
         + 4u * cast(uint)(x == y)
         + 8u * cast(uint)(x != y)
         + 16u * cast(uint)(x > y)
         + 32u * cast(uint)(x >= y);
}
