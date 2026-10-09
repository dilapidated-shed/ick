module scalar_memory;

version (Android) {} else static assert(0, "Android version must be predefined");
version (ARM) {} else static assert(0, "ARM version must be predefined");
version (ARM_SoftFP) {} else static assert(0, "base PCS must be selected");
version (CRuntime_Bionic) {} else static assert(0, "Bionic must be selected");
version (D_ModuleInfo) {} else static assert(0, "ordinary D must retain ModuleInfo");
static assert(void*.sizeof == 4);
static assert(bool.sizeof == 1);
static assert(int.sizeof == 4 && float.sizeof == 4);
static assert(long.sizeof == 8 && ulong.sizeof == 8 && double.sizeof == 8);

// Compile without -betterC. The separately authored assembly owns all pointer
// targets, checks every result word and byte sentinel, and supplies a TEST-ONLY
// ModuleInfo registration oracle. No Android druntime implementation is implied.
// MemoryBaseline excludes only accesses rejected by the pre-fix compiler, so
// accepted-but-wrong long loads/stores can be reproduced independently.

extern(C) __gshared long memory_own_long = 0x1020304050607080L;
extern(C) __gshared double memory_own_double = 3.5;

extern(C) long memory_load_long(long* address)
{
    version (MemoryWrongHighReturn)
        return cast(long)cast(uint)*address;
    else
        return *address;
}

extern(C) ulong memory_load_ulong(ulong* address) { return *address; }
extern(C) double memory_load_double(double* address) { return *address; }

extern(C) long memory_store_long(long* address, long value)
{
    version (MemoryTruncatedStore)
    {
        // An intentionally broken SOURCE program, not a compiler patch. The
        // assembly must reject its unchanged high memory word at stage 4 even
        // though it returns the complete input value.
        *cast(uint*)address = cast(uint)value;
        return value;
    }
    else
        return *address = value;
}

extern(C) ulong memory_store_ulong(ulong* address, ulong value)
{
    return *address = value;
}

extern(C) double memory_store_double(double* address, double value)
{
    return *address = value;
}

extern(C) int memory_load_int(int* address) { return *address; }
extern(C) int memory_store_int(int* address, int value) { return *address = value; }
extern(C) float memory_load_float(float* address) { return *address; }
extern(C) float memory_store_float(float* address, float value) { return *address = value; }
extern(C) int* memory_load_pointer(int** address) { return *address; }
extern(C) int* memory_store_pointer(int** address, int* value) { return *address = value; }

// These callbacks deliberately overwrite caller-saved core and VFP registers.
// The compiler must preserve the RHS until the destination address is known,
// and return the assignment value after storing it.
extern(C) long* memory_address_long(long* address);
extern(C) ulong* memory_address_ulong(ulong* address);
extern(C) double* memory_address_double(double* address);

extern(C) long memory_store_long_after_call(long* address, long value)
{
    return *memory_address_long(address) = value;
}

extern(C) ulong memory_store_ulong_after_call(ulong* address, ulong value)
{
    return *memory_address_ulong(address) = value;
}

extern(C) double memory_store_double_after_call(double* address, double value)
{
    return *memory_address_double(address) = value;
}

version (MemoryBaseline) {} else
{
    extern(C) bool memory_load_bool(bool* address) { return *address; }
    extern(C) bool memory_store_bool(bool* address, bool value) { return *address = value; }

    extern(C) __gshared bool memory_own_bool_true = true;
    extern(C) __gshared bool memory_own_bool_false = false;
    extern(C) align(16) __gshared bool memory_own_bool_aligned = true;
    extern(C) extern __gshared bool memory_external_bool;

    extern(C) bool memory_load_own_bool_true() { return memory_own_bool_true; }
    extern(C) bool memory_load_own_bool_false() { return memory_own_bool_false; }
    extern(C) bool memory_store_own_bool_true(bool value) { return memory_own_bool_true = value; }
    extern(C) bool memory_store_own_bool_false(bool value) { return memory_own_bool_false = value; }
    extern(C) bool memory_load_external_bool() { return memory_external_bool; }
    extern(C) bool memory_store_external_bool(bool value) { return memory_external_bool = value; }

    extern(C) long memory_index_long(long* address, int index) { return address[index]; }
    extern(C) long memory_index_store_long(long* address, int index, long value)
    {
        return address[index] = value;
    }

    extern(C) ulong memory_index_ulong(ulong* address, int index) { return address[index]; }
    extern(C) ulong memory_index_store_ulong(ulong* address, int index, ulong value)
    {
        return address[index] = value;
    }

    extern(C) double memory_index_double(double* address, int index) { return address[index]; }
    extern(C) double memory_index_store_double(double* address, int index, double value)
    {
        return address[index] = value;
    }

    extern(C) bool memory_index_bool(bool* address, int index) { return address[index]; }
    extern(C) bool memory_index_store_bool(bool* address, int index, bool value)
    {
        return address[index] = value;
    }

    extern(C) int memory_index_int(int* address, int index) { return address[index]; }
    extern(C) int memory_index_store_int(int* address, int index, int value)
    {
        return address[index] = value;
    }

    extern(C) float memory_index_float(float* address, int index) { return address[index]; }
    extern(C) float memory_index_store_float(float* address, int index, float value)
    {
        return address[index] = value;
    }

    extern(C) int* memory_index_pointer(int** address, int index) { return address[index]; }
    extern(C) int* memory_index_store_pointer(int** address, int index, int* value)
    {
        return address[index] = value;
    }

    extern(C) bool* memory_address_bool(bool* address);
    extern(C) int memory_index();

    // Two independent calls in the destination also require retaining the base
    // pointer while the index is evaluated. The oracle returns index -1.
    extern(C) long memory_index_store_long_after_calls(long* address, long value)
    {
        return memory_address_long(address)[memory_index()] = value;
    }

    extern(C) double memory_index_store_double_after_calls(double* address, double value)
    {
        return memory_address_double(address)[memory_index()] = value;
    }

    extern(C) bool memory_index_store_bool_after_calls(bool* address, bool value)
    {
        return memory_address_bool(address)[memory_index()] = value;
    }
}
