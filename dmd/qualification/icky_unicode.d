module icky_unicode_acceptance;

extern(C) int main()
{
    int left;
    left ← 4;

    int right;
    3 → right;

    auto square = λ(int x) ⇒ x²;
    auto cube = λ(int x) ⇒ x³;

    if (left ≠ 4)
        return 1;
    if (!(right ≟ 3))
        return 2;
    if (!(square(right) ≟ 9))
        return 3;
    if (!(cube(2) ≟ 8))
        return 4;
    if (!(3 × 4 ≟ 12))
        return 5;
    if (!(6 ÷ 3 ≟ 2))
        return 6;
    if (!(−3 + 4 ≟ 1))
        return 7;

    return 0;
}
