module ordinary_d_calls;

import ordinary_d_linkage;
static import ordinary_d_peer;

// Globals keep the already qualified C linkage/non-TLS boundary. The functions
// below use ordinary D linkage unless they explicitly exercise the C boundary.
extern(C) __gshared int ordinary_d_trace = 0;
extern(C) int ordinary_d_c_twice(int value);

// These declarations are implemented independently in A32 assembly. Passing
// compiler-generated callers and callees alone could conceal a shared ABI bug.
int asmScalar(int first, int second, int third, int fourth, int fifth);
float asmFloat(float first, float second, float third, float fourth, float fifth);
double asmDouble(int first, double value, int tail);
long asmLong(int first, int second, int third, long value);
int* asmPointer(int* value);
double asmStackDouble(int first, int second, int third, int fourth, int fifth,
                      double value, int tail);

int crossModules()
{
    return ordinary_d_identity(21) + ordinary_d_peer.ordinary_d_identity(21);
}

int callOverloads()
{
    return overloaded(3) + cast(int)overloaded(4L);
}

int callC(int value) { return ordinary_d_c_twice(ordinary_d_identity(value)); }
extern(C) int ordinary_d_c_calls_d(int value) { return ordinary_d_identity(value) + 1; }

int mark(int value)
{
    ordinary_d_trace = ordinary_d_trace * 10 + value;
    return value;
}

int order()
{
    ordinary_d_trace = 0;
    int result = asmScalar(mark(1), mark(2), mark(3), mark(4), mark(5));
    return result + ordinary_d_trace;
}

float callFloat()
{
    return fifthFloat(1.0f, 2.0f, 3.0f, 4.0f, 5.0f) +
           asmFloat(1.0f, 2.0f, 3.0f, 4.0f, 5.0f);
}

double callDouble()
{
    return alignedDouble(1, 3.5, 3) + asmDouble(1, 3.5, 3);
}

long callLong()
{
    return stackedLong(1, 2, 3, asmLong(1, 2, 3, 0x1122334455667788L));
}

int* callPointer(int* value) { return pointer(asmPointer(value)); }

double callStackDouble()
{
    return stackAlignedDouble(1, 2, 3, 4, 5, 6.25, 7) +
           asmStackDouble(1, 2, 3, 4, 5, 6.25, 7);
}

int callQualified() { return qualified(custom(34)); }
