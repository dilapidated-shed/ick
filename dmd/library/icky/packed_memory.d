/**
 * Representation-aware scalar operations over packed coordinate slices.
 *
 * Storage remains E5M3 or E3M2. E5M3 +, - and narrow * have a direct
 * checked path that never widens through Float16 or binary32. Explicit
 * Float16 computation remains available where the caller actually requests
 * a wider result.
 */
module icky.packed_memory;

import icky.imprecise;
import icky.packed : packed_read, packed_write;

nothrow @nogc:

extern(C) void abort() nothrow @nogc;

private enum supported_storage(T) =
    is(T == E5M3) || is(T == E3M2) ||
    is(T == const(E5M3)) || is(T == const(E3M2));

private enum both_e5m3(Left, Right) =
    (is(Left == E5M3) || is(Left == const(E5M3))) &&
    (is(Right == E5M3) || is(Right == const(E5M3)));

private enum float16_operation_allowed(string operation, Left, Right) =
    (operation == "+" || operation == "-" || operation == "*" || operation == "/") &&
    !(both_e5m3!(Left, Right) && (operation == "+" || operation == "-"));

private enum direct_e5m3_operation(string operation) =
    operation == "+" || operation == "-" || operation == "*";

/* A precondition failure has no allocation and cannot perform a packed read.
 * The public store operation has a boolean failure result; compute_at has the
 * fixed Float16 result required by the contract, so its invalid-index path is
 * deliberately a failing precondition rather than a second result channel.
 */
private Float16 invalid_compute_index()
{
    // Keep a hard failure in release and bounds-disabled BetterC builds,
    // without relying on D assertions.
    abort();
    // Retain the non-returning contract if a non-conforming abort returns.
    for (;;) {}
}

private Float16 decode_operand(T)(T value)
    if (supported_storage!T)
{
    return Float16.from_float(value.to_float());
}

private Float16 perform_float16_operation(string operation)(Float16 left, Float16 right)
    if (operation == "+" || operation == "-" || operation == "*" || operation == "/")
{
    static if (operation == "+") return left + right;
    else static if (operation == "-") return left - right;
    else static if (operation == "*") return left * right;
    else return left / right;
}

/**
 * The compiler-owned seam is kept at this scalar operation boundary.  The
 * ordinary body is also a complete allocation-free fallback for function
 * addresses and compilers which do not yet install a target follower.
 */
pragma(inline, false)
private Float16 packed_compute_at(string operation, Left, Right)(
    const(Left)[] left, size_t leftIndex,
    const(Right)[] right, size_t rightIndex)
    if (supported_storage!Left && supported_storage!Right &&
        float16_operation_allowed!(operation, Left, Right))
{
    if (leftIndex >= left.length || rightIndex >= right.length)
        return invalid_compute_index();

    // Each requested packed coordinate is loaded exactly once.  These calls
    // are the concrete scalar memory followers for the complete request.
    auto left_stored = packed_read!(Left, Float16, 1, 0)(
        cast(const(ubyte)*)left.ptr, left.length * Left.sizeof,
        leftIndex, Left.sizeof);
    auto right_stored = packed_read!(Right, Float16, 1, 0)(
        cast(const(ubyte)*)right.ptr, right.length * Right.sizeof,
        rightIndex, Right.sizeof);
    auto left_arithmetic = decode_operand(left_stored);
    auto right_arithmetic = decode_operand(right_stored);
    return perform_float16_operation!operation(left_arithmetic, right_arithmetic);
}

/**
 * Compute one Float16 result from two represented coordinates.  `Arithmetic`
 * is explicit so unsupported arithmetic formats cannot silently select a
 * different carrier.  No overload accepts or returns a whole widened slice.
 */
pragma(inline, false)
Float16 compute_at(Arithmetic, string operation, Left, Right)(
    const(Left)[] left, size_t leftIndex,
    const(Right)[] right, size_t rightIndex)
    if (is(Arithmetic == Float16) && supported_storage!Left &&
        supported_storage!Right &&
        float16_operation_allowed!(operation, Left, Right))
{
    // Validate both indices before passing the call to the representation
    // follower or touching either packed element.
    if (leftIndex >= left.length || rightIndex >= right.length)
        return invalid_compute_index();
    return packed_compute_at!operation(left, leftIndex, right, rightIndex);
}

/**
 * Compute one checked E5M3 result without widening either operand.
 *
 * Bounds or representation-domain failure returns false and preserves output.
 * Addition/subtraction use the exact common E5M3 dyadic lattice. Multiplication
 * widens only the integer significand product needed for that one operation,
 * then immediately requantizes to E5M3.
 */
pragma(inline, false)
bool try_e5m3_at(string operation)(
    const(E5M3)[] left, size_t leftIndex,
    const(E5M3)[] right, size_t rightIndex,
    ref E5M3 output)
    if (direct_e5m3_operation!operation)
{
    if (leftIndex >= left.length || rightIndex >= right.length)
        return false;

    const leftValue = left[leftIndex];
    const rightValue = right[rightIndex];
    E5M3 candidate;
    bool accepted;
    static if (operation == "+")
        accepted = E5M3.try_add(leftValue, rightValue, candidate);
    else static if (operation == "-")
        accepted = E5M3.try_subtract(leftValue, rightValue, candidate);
    else
        accepted = E5M3.try_multiply(leftValue, rightValue, candidate);

    if (!accepted)
        return false;
    output = candidate;
    return true;
}

/** Scalar compiler-seam body for one checked packed store. */
pragma(inline, false)
private bool packed_store_at(Storage)(Storage[] destination, size_t index, Float16 value)
    if (supported_storage!Storage)
{
    if (index >= destination.length)
        return false;

    Storage encoded;
    static if (is(Storage == E5M3))
    {
        if (!Storage.try_from_float(value.to_float(), encoded))
            return false;
    }
    else
    {
        // E3M2's established quantizer is total: saturation and NaN mapping
        // remain its existing semantics, including unused-bit normalization.
        encoded = Storage.from_float(value.to_float());
    }
    packed_write!(Storage, Float16, 1, 0)(
        cast(ubyte*)destination.ptr, destination.length * Storage.sizeof,
        index, Storage.sizeof, encoded);
    return true;
}

/**
 * Encode one Float16 value into one E5M3 or E3M2 coordinate.  The destination
 * is writable by type, and a failed E5M3 encoding leaves its byte untouched.
 */
pragma(inline, false)
bool try_store_at(Storage)(Storage[] destination, size_t index, Float16 value)
    if (supported_storage!Storage)
{
    if (index >= destination.length)
        return false;
    return packed_store_at(destination, index, value);
}
