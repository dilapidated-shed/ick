module ordinary_d_unsupported;

// Compile each version separately. Each source must pass frontend semantics,
// then fail at the backend and remove a deliberately stale output object.
version (RefDefinition)
    int unsupported(ref int value) { return value; }
version (RefCall)
{
    int unsupported(ref int value);
    int caller(int value) { return unsupported(value); }
}
version (OutCall)
{
    int unsupported(out int value);
    int caller(int value) { return unsupported(value); }
}
version (LazyCall)
{
    int unsupported(lazy int value);
    int caller(int value) { return unsupported(value); }
}
version (RefReturn)
{
    extern(C) __gshared int value;
    ref int unsupported() { return value; }
}
version (VariadicCall)
{
    int unsupported(int value, ...);
    int caller() { return unsupported(1, 2); }
}
version (AggregateResult)
    int[] unsupported() { return null; }
version (NestedCall)
{
    int caller(int value)
    {
        int nested() { return value; }
        return nested();
    }
}
version (DMainInt)
    int main() { return 0; }
version (DMainVoid)
    void main() {}
version (CrtConstructor)
    pragma(crt_constructor) void startup() {}
version (CrtDestructor)
    pragma(crt_destructor) void shutdown() {}
version (DisabledUnittest)
{
    unittest {}
    int identity(int value) { return value; }
}

// Pointer storage support remains limited to the qualified scalar widths.
version (AggregatePointerElement)
    void unsupported(int[2]* destination, int[2]* source) { *destination = *source; }
version (NarrowPointerElement)
    int unsupported(short* source) { return *source; }
version (VectorPointerIndex)
{
    alias float4 = __vector(float[4]);
    void unsupported(float4* destination, float4* source) { destination[1] = source[1]; }
}
version (TlsBoolGlobal)
{
    bool flag;
    bool unsupported() { return flag; }
}
