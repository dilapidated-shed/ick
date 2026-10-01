module thumb_call;

version (Android) {} else static assert(0, "Android target missing");
version (ARM) {} else static assert(0, "ARM target missing");
version (ARM_Thumb) {} else static assert(0, "Thumb target missing");

extern(C):

float pauli_external_scale(float value);

float pauli_thumb_call_external(float value)
{
    return pauli_external_scale(value) + 1.0f;
}
