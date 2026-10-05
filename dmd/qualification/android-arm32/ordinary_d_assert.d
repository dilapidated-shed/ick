module ordinary_d_assert;

extern(C) export int ordinary_d_checked(int value)
{
    assert(value > 0);
    return value;
}
