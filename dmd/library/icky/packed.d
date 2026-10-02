/**
 * Scalar access to packed numeric storage.
 *
 * A view retains the storage and arithmetic types separately and fetches one
 * element per operation. `Alignment` and `AliasSet` describe caller-known
 * memory facts; they never select an instruction or alter the value semantics.
 */
module icky.packed;

import icky.imprecise;

enum PackedEffect : ubyte
{
    read = 1,
    write = 2,
}

enum PackedOrdering : ubyte
{
    ordinary,
}

enum PackedAction : ubyte
{
    load,
    decode,
    arithmetic,
    encode,
    store,
}

pragma(inline, false)
package Storage packed_read(Storage, Arithmetic, size_t Alignment, uint AliasSet)(
    const(ubyte)* base, size_t byteLength, size_t elementIndex, size_t byteStride)
    nothrow @nogc
{
    assert(byteStride == 0 || elementIndex <= size_t.max / byteStride);
    const offset = elementIndex * byteStride;
    assert(offset <= byteLength && Storage.sizeof <= byteLength - offset);
    return *cast(const(Storage)*)(base + offset);
}

pragma(inline, false)
package void packed_write(Storage, Arithmetic, size_t Alignment, uint AliasSet)(
    ubyte* base, size_t byteLength, size_t elementIndex, size_t byteStride, Storage value)
    nothrow @nogc
{
    assert(byteStride == 0 || elementIndex <= size_t.max / byteStride);
    const offset = elementIndex * byteStride;
    assert(offset <= byteLength && Storage.sizeof <= byteLength - offset);
    *cast(Storage*)(base + offset) = value;
}

/** Typed semantic and memory description for one scalar packed operation. */
struct PackedOperation(Storage, Arithmetic)
{
    PackedAction action;
    const(ubyte)* base;
    size_t byteLength;
    size_t elementIndex;
    size_t byteStride;
    size_t knownAlignment;
    uint aliasSet;
    PackedEffect effect;
    PackedOrdering ordering;

    alias storage_type = Storage;
    alias arithmetic_type = Arithmetic;
}

/** A stored element and its separate arithmetic representation. */
struct PackedValue(Storage, Arithmetic)
{
    Storage stored;

    Arithmetic decode() const nothrow @nogc
    {
        return Arithmetic.from_float(stored.to_float());
    }

    static bool try_encode(Arithmetic value, ref Storage output) nothrow @nogc
    {
        static if (__traits(compiles, Storage.try_from_float(value.to_float(), output)))
            return Storage.try_from_float(value.to_float(), output);
        else
        {
            output = Storage.from_float(value.to_float());
            return true;
        }
    }
}

/**
 * A byte-addressed view over scalar packed values.
 *
 * The view stores only a byte pointer, byte length, and byte stride. It never
 * materializes an arithmetic-representation array. Each successful `try_load`
 * reads exactly one Storage value; decode occurs only when the caller asks
 * the returned PackedValue to decode.
 *
 * `Alignment` must be a power of two and is a caller assertion about `base`.
 * `AliasSet` is an analysis label, not a promise of non-aliasing. Zero means
 * unknown. The current memory operations are ordinary sequenced reads/writes.
 */
struct PackedView(Storage, Arithmetic, size_t Alignment = 1, uint AliasSet = 0)
{
    ubyte* base;
    size_t byteLength;
    size_t byteStride;

    alias storage_type = Storage;
    alias arithmetic_type = Arithmetic;
    enum known_alignment = Alignment;
    enum alias_set = AliasSet;

    static assert(Alignment != 0 && (Alignment & (Alignment - 1)) == 0,
                  "packed alignment must be a power of two");
    static assert(Storage.sizeof != 0);

    private bool byte_offset(size_t elementIndex, out size_t offset) const nothrow @nogc
    {
        if (byteStride != 0 && elementIndex > size_t.max / byteStride)
            return false;
        offset = elementIndex * byteStride;
        return offset <= byteLength && Storage.sizeof <= byteLength - offset;
    }

    bool try_load(size_t elementIndex, ref PackedValue!(Storage, Arithmetic) output)
        const nothrow @nogc
    {
        size_t offset;
        if (!byte_offset(elementIndex, offset))
            return false;

        Storage value = packed_read!(Storage, Arithmetic, Alignment, AliasSet)(
            base, byteLength, elementIndex, byteStride);
        output.stored = value;
        return true;
    }

    bool try_store(size_t elementIndex, Arithmetic value) nothrow @nogc
    {
        size_t offset;
        if (!byte_offset(elementIndex, offset))
            return false;

        Storage encoded;
        if (!PackedValue!(Storage, Arithmetic).try_encode(value, encoded))
            return false;

        packed_write!(Storage, Arithmetic, Alignment, AliasSet)(
            base, byteLength, elementIndex, byteStride, encoded);
        return true;
    }

    PackedOperation!(Storage, Arithmetic) load_operation(size_t elementIndex) const nothrow @nogc
    {
        return PackedOperation!(Storage, Arithmetic)(
            PackedAction.load, base, byteLength, elementIndex, byteStride,
            Alignment, AliasSet, PackedEffect.read, PackedOrdering.ordinary);
    }

    PackedOperation!(Storage, Arithmetic) store_operation(size_t elementIndex) nothrow @nogc
    {
        return PackedOperation!(Storage, Arithmetic)(
            PackedAction.store, base, byteLength, elementIndex, byteStride,
            Alignment, AliasSet, PackedEffect.write, PackedOrdering.ordinary);
    }
}

static assert(PackedValue!(UE5M3, Float16).sizeof == UE5M3.sizeof);
static assert(PackedView!(UE5M3, Float16, 1).sizeof <= 4 * size_t.sizeof);
