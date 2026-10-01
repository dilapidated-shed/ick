module byte_rgb;

version (Android) {} else static assert(0, "Android target missing");

extern(C):

uint pauli_byte_roundtrip(ubyte* pixels, uint index, uint value)
{
    ubyte stored = cast(ubyte)value;
    pixels[index] = stored;
    return cast(uint)pixels[index];
}
