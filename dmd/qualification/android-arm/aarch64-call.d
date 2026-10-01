module aarch64_call;

version (Android) {} else static assert(0, "Android target missing");
version (AArch64) {} else static assert(0, "AArch64 target missing");

extern(C):

float pauli_external_scale(float value);

float pauli_call_external(float value)
{
    return pauli_external_scale(value) + 1.0f;
}
