/**
 * Typed, target-independent description of one packed-memory operation.
 *
 * This is a narrow lowering request, not a general expression IR. It remains
 * intact until `lowerPackedMemory` has selected the conservative scalar path.
 * Future target followers can consume the same request before that fallback.
 */
module dmd.packedmemory;

import dmd.expression : Expression;
import dmd.mtype : Type;

enum PackedMemoryAction : ubyte
{
    load,
    decode,
    arithmetic,
    encode,
    store,
}

enum PackedConversionPolicy : ubyte
{
    representation_defined,
}

enum PackedMemoryEffect : ubyte
{
    read,
    write,
}

enum PackedMemoryOrdering : ubyte
{
    ordinary_source_order,
}

/** All semantic, representation, and memory facts needed by a scalar follower. */
struct PackedMemoryOperation
{
    bool valid;
    PackedMemoryAction action;

    // Representation facts. Type identity carries the existing format rules;
    // storageBytes and alignment make physical layout facts directly visible.
    Type sourceStorage;
    Type arithmeticRepresentation;
    Type destinationStorage;
    size_t storageBytes;
    size_t storageAlignment;

    // Memory facts, expressed as already type-checked D expressions.
    Expression baseAddress;
    Expression byteLength;
    Expression elementIndex;
    Expression byteStride;
    Expression storedValue;
    size_t knownAlignment;
    uint aliasSet;

    // Conversion and effect facts. Target properties do not appear here.
    PackedConversionPolicy conversion;
    PackedMemoryEffect effect;
    PackedMemoryOrdering ordering;
}
