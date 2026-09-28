/** Complex projective points with explicit numerical equivalence.
 * CPn!n has n+1 homogeneous coordinates. The stored representative is unit
 * length with the largest coordinate made positive real (first wins ties).
 * This is the binary32 semantic follower, not a packed CP2 codec.
 */
module icky.projective;

import core.stdc.math : sqrtf, fabsf;
import icky.geometry : finite_float;

nothrow @nogc:

struct Complex32
{
    nothrow @nogc:
    float real_part = 0.0f;
    float imaginary_part = 0.0f;
    Complex32 opBinary(string operation)(Complex32 other) const
        if (operation == "+" || operation == "-" || operation == "*")
    {
        static if (operation == "+")
            return Complex32(real_part + other.real_part, imaginary_part + other.imaginary_part);
        else static if (operation == "-")
            return Complex32(real_part - other.real_part, imaginary_part - other.imaginary_part);
        else
            return Complex32(real_part * other.real_part - imaginary_part * other.imaginary_part,
                             real_part * other.imaginary_part + imaginary_part * other.real_part);
    }
}

struct CPn(size_t dimension)
{
    nothrow @nogc:
    static assert(dimension < size_t.max);
    enum size_t coordinate_count = dimension + 1;
    private static Complex32[coordinate_count] origin()
    {
        Complex32[coordinate_count] result;
        result[0] = Complex32(1.0f, 0.0f);
        return result;
    }
    private Complex32[coordinate_count] representative = origin();

    static bool try_from_homogeneous(Complex32[coordinate_count] input, ref CPn output)
    {
        float largest_component = 0.0f;
        foreach (coordinate; input)
        {
            if (!finite_float(coordinate.real_part) || !finite_float(coordinate.imaginary_part))
                return false;
            if (fabsf(coordinate.real_part) > largest_component)
                largest_component = fabsf(coordinate.real_part);
            if (fabsf(coordinate.imaginary_part) > largest_component)
                largest_component = fabsf(coordinate.imaginary_part);
        }
        if (largest_component == 0.0f) return false;
        Complex32[coordinate_count] scaled;
        float squared_length = 0.0f;
        float largest_squared = -1.0f;
        size_t pivot = 0;
        foreach (index; 0 .. coordinate_count)
        {
            scaled[index] = Complex32(input[index].real_part / largest_component,
                                      input[index].imaginary_part / largest_component);
            float squared = scaled[index].real_part * scaled[index].real_part +
                            scaled[index].imaginary_part * scaled[index].imaginary_part;
            squared_length += squared;
            if (squared > largest_squared)
            {
                largest_squared = squared;
                pivot = index;
            }
        }
        float length = sqrtf(squared_length);
        float pivot_length = sqrtf(largest_squared);
        if (!finite_float(length) || length == 0.0f) return false;
        Complex32 remove_phase = Complex32(scaled[pivot].real_part / pivot_length,
                                          -scaled[pivot].imaginary_part / pivot_length);
        CPn candidate;
        foreach (index; 0 .. coordinate_count)
        {
            auto rotated = scaled[index] * remove_phase;
            candidate.representative[index] = Complex32(rotated.real_part / length,
                                                       rotated.imaginary_part / length);
        }
        candidate.representative[pivot] = Complex32(pivot_length / length, 0.0f);
        output = candidate;
        return true;
    }

    // An explicit representative, not the definition of equality of points.
    Complex32[coordinate_count] homogeneous_coordinates() const { return representative; }

    /** Chordal projective distance: ||z wedge w|| for normalized representatives.
     * This avoids cancellation in sqrt(1 - |<z,w>|^2) near equal points and
     * remains meaningful across a change in the chosen largest-coordinate chart.
     */
    float distance(CPn other) const
    {
        float squared = 0.0f;
        foreach (first; 0 .. coordinate_count)
            foreach (second; first + 1 .. coordinate_count)
            {
                auto minor = representative[first] * other.representative[second] -
                             representative[second] * other.representative[first];
                squared += minor.real_part * minor.real_part +
                           minor.imaginary_part * minor.imaginary_part;
            }
        return sqrtf(squared);
    }
    bool same_point(CPn other, float tolerance) const
    {
        return finite_float(tolerance) && tolerance >= 0.0f && distance(other) <= tolerance;
    }
    // Approximate closeness is not transitive, and byte equality would compare
    // representatives instead of projective points. Neither becomes operator ==.
    @disable bool opEquals(ref const CPn other) const;

    /** Divide by the selected homogeneous coordinate, omitting it in output.
     * Reject a zero chart denominator or coordinates not representable in F32.
     * Every failed checked operation leaves output unchanged.
     */
    bool try_chart(size_t pivot, ref Complex32[dimension] output) const
    {
        if (pivot >= coordinate_count) return false;
        auto divisor = representative[pivot];
        float scale = fabsf(divisor.real_part);
        if (fabsf(divisor.imaginary_part) > scale) scale = fabsf(divisor.imaginary_part);
        if (scale == 0.0f) return false;
        float divisor_real = divisor.real_part / scale;
        float divisor_imaginary = divisor.imaginary_part / scale;
        float denominator = divisor_real * divisor_real + divisor_imaginary * divisor_imaginary;
        Complex32[dimension] candidate;
        size_t cursor = 0;
        foreach (index; 0 .. coordinate_count)
        {
            if (index == pivot) continue;
            auto coordinate = representative[index];
            float result_real = ((coordinate.real_part * divisor_real + coordinate.imaginary_part * divisor_imaginary) /
                                 denominator) / scale;
            float result_imaginary = ((coordinate.imaginary_part * divisor_real - coordinate.real_part * divisor_imaginary) /
                                      denominator) / scale;
            if (!finite_float(result_real) || !finite_float(result_imaginary)) return false;
            candidate[cursor++] = Complex32(result_real, result_imaginary);
        }
        output = candidate;
        return true;
    }
}

alias CP1 = CPn!1;
alias CP2 = CPn!2;
static assert(CP2.coordinate_count == 3 && !is(CP1 == CP2));
