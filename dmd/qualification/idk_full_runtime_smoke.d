module idk_full_runtime_smoke;

import std.bigint : BigInt;
import std.stdio : writeln;

class Box
{
    BigInt value;

    this(BigInt value)
    {
        this.value = value;
    }
}

int main()
{
    int n;
    5 → n;

    auto square = λ(int x) ⇒ x²;
    if (!(square(n) ≟ 25))
        return 1;

    auto box = new Box(BigInt("999999999999999999999999999999"));

    try
    {
        throw new Exception("idk-full-runtime");
    }
    catch (Exception error)
    {
        if (error.msg != "idk-full-runtime")
            return 2;
    }

    box.value += 1;
    writeln(box.value);

    if (!(3 × 4 ≟ 12))
        return 3;
    if (!(−3 + 4 ≟ 1))
        return 4;

    return box.value == BigInt("1000000000000000000000000000000") ? 0 : 5;
}
