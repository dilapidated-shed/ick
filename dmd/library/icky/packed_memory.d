/**
 * Representation-aware scalar operations over packed coordinate slices.
 *
 * Storage remains UE5M3 or E3M2. Arithmetic is explicit: callers may select
 * Float16 or signed E5M3. Conversion happens only for coordinates consumed by
 * the current scalar operation; no widened input array is materialized.
 */
module icky.packed_memory;

import icky.imprecise;
import icky.packed : packed_read, packed_write;

nothrow @nogc:

extern(C) void abort() nothrow @nogc;

private enum supported_storage(T) =
    is(T == UE5M3) || is(T == E3M2) ||
    is(T == const(UE5M3)) || is(T == const(E3M2));

private enum supported_arithmetic(T) =
    is(T == Float16) || is(T == E5M3);

private enum supported_operation(Arithmetic, string operation) =
    is(Arithmetic == Float16)
        ? (operation == "+" || operation == "-" ||
           operation == "*" || operation == "/")
        : is(Arithmetic == E5M3)
            ? (operation == "+" || operation == "-")
            : false;

/* A precondition failure has no allocation and cannot perform a packed read.
 * compute_at has a fixed scalar result selected by its Arithmetic template,
 * so an invalid index deliberately fails rather than inventing a value.
 */
private Arithmetic invalid_compute_index(Arithmetic)()
    if (supported_arithmetic!Arithmetic)
{
    abort();
    for (;;) {}
}

private Arithmetic decode_operand(Arithmetic, T)(T value)
    if (supported_arithmetic!Arithmetic && supported_storage!T)
{
    return Arithmetic.from_float(value.to_float());
}

private Arithmetic perform_operation(Arithmetic, string operation)(
    Arithmetic left, Arithmetic right)
    if (supported_operation!(Arithmetic, operation))
{
    static if (operation == "+") return left + right;
    else static if (operation == "-") return left - right;
    else static if (operation == "*") return left * right;
    else return left / right;
}

/**
 * The compiler-owned seam is kept at this scalar operation boundary. The
 * ordinary body is also a complete allocation-free fallback for function
 * addresses and compilers which do not yet install a target follower.
 */
pragma(inline, false)
private Arithmetic packed_compute_at(Arithmetic, string operation, Left, Right)(
    const(Left)[] left, size_t leftIndex,
    const(Right)[] right, size_t rightIndex)
    if (supported_operation!(Arithmetic, operation) &&
        supported_storage!Left && supported_storage!Right)
{
    if (leftIndex >= left.length || rightIndex >= right.length)
        return invalid_compute_index!Arithmetic();

    // Each requested packed coordinate is loaded exactly once. Arithmetic
    // identity is retained by the compiler request and the byte-load follower.
    auto left_stored = packed_read!(Left, Arithmetic, 1, 0)(
        cast(const(ubyte)*)left.ptr, left.length * Left.sizeof,
        leftIndex, Left.sizeof);
    auto right_stored = packed_read!(Right, Arithmetic, 1, 0)(
        cast(const(ubyte)*)right.ptr, right.length * Right.sizeof,
        rightIndex, Right.sizeof);
    auto left_arithmetic = decode_operand!(Arithmetic)(left_stored);
    auto right_arithmetic = decode_operand!(Arithmetic)(right_stored);
    return perform_operation!(Arithmetic, operation)(
        left_arithmetic, right_arithmetic);
}

/**
 * Compute one scalar result from two represented coordinates. Arithmetic is
 * explicit so no operation can silently select Float16. In particular,
 * compute_at!(E5M3, "-") returns signed E5M3 even when the result is negative.
 * E5M3 multiplication/division are intentionally not overloads here; select
 * Float16 explicitly for those operations.
 */
pragma(inline, false)
Arithmetic compute_at(Arithmetic, string operation, Left, Right)(
    const(Left)[] left, size_t leftIndex,
    const(Right)[] right, size_t rightIndex)
    if (supported_operation!(Arithmetic, operation) &&
        supported_storage!Left && supported_storage!Right)
{
    if (leftIndex >= left.length || rightIndex >= right.length)
        return invalid_compute_index!Arithmetic();
    return packed_compute_at!(Arithmetic, operation)(
        left, leftIndex, right, rightIndex);
}

/** Scalar compiler-seam body for one checked packed store. */
pragma(inline, false)
private bool packed_store_at(Storage, Arithmetic)(
    Storage[] destination, size_t index, Arithmetic value)
    if (supported_storage!Storage && supported_arithmetic!Arithmetic)
{
    if (index >= destination.length)
        return false;

    Storage encoded;
    static if (is(Storage == UE5M3))
    {
        // UE5M3 is positive storage. Negative E5M3 results, signed zeros,
        // infinities, NaNs, and other values outside its encoder domain fail
        // explicitly and preserve the destination byte.
        if (!Storage.try_from_float(value.to_float(), encoded))
            return false;
    }
    else
    {
        // E3M2's established quantizer is total: saturation and NaN mapping
        // remain its existing semantics, including unused-bit normalization.
        encoded = Storage.from_float(value.to_float());
    }
    packed_write!(Storage, Arithmetic, 1, 0)(
        cast(ubyte*)destination.ptr, destination.length * Storage.sizeof,
        index, Storage.sizeof, encoded);
    return true;
}

/**
 * Encode one Float16 or signed E5M3 scalar into one UE5M3 or E3M2 coordinate.
 * A failed UE5M3 encoding returns false and leaves its byte untouched.
 */
pragma(inline, false)
bool try_store_at(Storage, Arithmetic)(
    Storage[] destination, size_t index, Arithmetic value)
    if (supported_storage!Storage && supported_arithmetic!Arithmetic)
{
    if (index >= destination.length)
        return false;
    return packed_store_at!(Storage, Arithmetic)(destination, index, value);
}
