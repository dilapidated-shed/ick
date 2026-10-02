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

enum PackedMemoryOperationKind : ubyte
{
    scalar_load,
    scalar_store,
    scalar_compute,
    checked_scalar_store,
}

enum PackedMemoryArithmetic : ubyte
{
    none,
    add,
    subtract,
    multiply,
    divide,
}

enum PackedMemoryRounding : ubyte
{
    none,
    float16_per_operation,
    e5m3_per_operation,
}

enum PackedMemoryDomain : ubyte
{
    total_quantization,
    partial_reject_preserve_destination,
}

enum PackedMemoryStage : uint
{
    load_packed = 1,
    decode = 2,
    arithmetic = 4,
    encode = 8,
    store_packed = 16,
}

/** All semantic, representation, and memory facts needed by a scalar follower. */
struct PackedMemoryOperation
{
    bool valid;
    PackedMemoryAction action;
    PackedMemoryOperationKind kind;
    PackedMemoryArithmetic arithmeticOperation;
    PackedMemoryRounding rounding;
    PackedMemoryDomain domain;
    uint stageMask;
    bool boundedTemporary;
    bool disjointProven;
    bool followerExecuted;
    bool publicSurface;

    // Representation facts. Type identity carries the existing format rules;
    // storageBytes and alignment make physical layout facts directly visible.
    Type leftStorage;
    Type rightStorage;
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
    Expression leftBase;
    Expression leftLength;
    Expression leftIndex;
    Expression leftStride;
    Expression rightBase;
    Expression rightLength;
    Expression rightIndex;
    Expression rightStride;
    Expression destinationBase;
    Expression destinationLength;
    Expression destinationIndex;
    Expression destinationStride;
    size_t knownAlignment;
    size_t leftAlignment;
    size_t rightAlignment;
    size_t destinationAlignment;
    size_t leftStrideBytes;
    size_t rightStrideBytes;
    size_t destinationStrideBytes;
    uint aliasSet;
    uint leftAliasSet;
    uint rightAliasSet;
    uint destinationAliasSet;

    // Conversion and effect facts. Target properties do not appear here.
    PackedConversionPolicy conversion;
    PackedMemoryEffect effect;
    PackedMemoryOrdering ordering;
}
