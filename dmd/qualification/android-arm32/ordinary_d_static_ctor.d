module ordinary_d_static_ctor;

// A static constructor makes normal-D ModuleInfo carry an initialization
// callback.  That representation remains outside this first ordinary-D A32
// object slice and must fail before an output object can survive.
static this()
{
}

extern(C) export int ordinary_d_static_ctor_value()
{
    return 1;
}
