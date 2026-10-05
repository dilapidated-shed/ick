module idk_ordinary_runtime_smoke;

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
    auto box = new Box(BigInt("123456789012345678901234567890"));
    try
    {
        throw new Exception("normal-d");
    }
    catch (Exception error)
    {
        if (error.msg != "normal-d")
            return 2;
    }
    box.value += 1;
    writeln(box.value);
    return box.value == BigInt("123456789012345678901234567891") ? 0 : 3;
}
