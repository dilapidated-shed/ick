module ordinary_d_linkage;

int ordinary_d_identity(int value) { return value; }

int overloaded(int value) { return value + 10; }
long overloaded(long value) { return value + 1000; }

int* pointer(int* value) { return value; }

float fifthFloat(float first, float second, float third, float fourth, float fifth)
{
    return fifth;
}

double alignedDouble(int first, double value, int tail)
{
    return value;
}

long stackedLong(int first, int second, int third, long value)
{
    return value;
}

double stackAlignedDouble(int first, int second, int third, int fourth, int fifth,
                          double value, int tail)
{
    return value;
}

pragma(mangle, "ordinary_d_custom") int custom(int value) { return value + 7; }

pure nothrow @safe @nogc int qualified(int value) { return value + 1; }
