private int evaluations;
private int direction_evaluations;

private float evaluated_value()
{
    ++evaluations;
    return -3.5f;
}

private struct Aggregate
{
    float[4] float_values;
    double[3] double_values;
    real[2] real_values;
}

private struct GenericAggregate(Element)
{
    Element[4] values;
}

private struct Direction(Frame)
{
    float[3] values = [1.0f, 0.0f, 0.0f];
}

private struct Phone {}

private Direction!Phone evaluated_direction()
{
    ++direction_evaluations;
    return Direction!Phone.init;
}

extern(C) int main()
{
    float[4] default_float;
    foreach (value; default_float)
        if (!(value is float.init))
            return 1;

    float[4] void_float = void;
    foreach (ref value; void_float)
        value = 7.0f;
    foreach (value; void_float)
        if (value != 7.0f)
            return 2;

    float[4] zero_float = 0.0f;
    foreach (value; zero_float)
        if (!(value is 0.0f))
            return 3;

    float[4] negative_zero_float = -0.0f;
    foreach (value; negative_zero_float)
        if (value != 0.0f || 1.0f / value >= 0.0f)
            return 4;

    double[4] default_double;
    foreach (value; default_double)
        if (!(value is double.init))
            return 5;

    double[2] void_double = void;
    foreach (ref value; void_double)
        value = 8.0;
    foreach (value; void_double)
        if (value != 8.0)
            return 6;

    double[4] zero_double = 0.0;
    foreach (value; zero_double)
        if (!(value is 0.0))
            return 7;

    double[4] negative_zero_double = -0.0;
    foreach (value; negative_zero_double)
        if (value != 0.0 || 1.0 / value >= 0.0)
            return 8;

    real[4] default_real;
    foreach (value; default_real)
        if (!(value is real.init))
            return 9;

    real[2] void_real = void;
    foreach (ref value; void_real)
        value = 9.0L;
    foreach (value; void_real)
        if (value != 9.0L)
            return 10;

    real[4] zero_real = 0.0L;
    foreach (value; zero_real)
        if (!(value is 0.0L))
            return 11;

    real[4] negative_zero_real = -0.0L;
    foreach (value; negative_zero_real)
        if (value != 0.0L || 1.0L / value >= 0.0L)
            return 12;

    Aggregate aggregate;
    foreach (value; aggregate.float_values)
        if (!(value is float.init))
            return 13;
    foreach (value; aggregate.double_values)
        if (!(value is double.init))
            return 14;
    foreach (value; aggregate.real_values)
        if (!(value is real.init))
            return 15;

    GenericAggregate!float generic_aggregate;
    foreach (value; generic_aggregate.values)
        if (!(value is float.init))
            return 16;

    Direction!Phone direction;
    if (!(direction.values[0] is 1.0f) ||
        !(direction.values[1] is 0.0f) ||
        !(direction.values[2] is 0.0f))
        return 17;

    Direction!Phone[4] directions;
    foreach (value; directions)
        if (!(value.values[0] is 1.0f) ||
            !(value.values[1] is 0.0f) ||
            !(value.values[2] is 0.0f))
            return 18;

    Direction!Phone[5] repeated_directions = void;
    repeated_directions[] = evaluated_direction();
    if (direction_evaluations != 1)
        return 19;
    foreach (value; repeated_directions)
        if (!(value.values[0] is 1.0f) ||
            !(value.values[1] is 0.0f) ||
            !(value.values[2] is 0.0f))
            return 20;

    float[2][3] nested;
    foreach (row; nested)
        foreach (value; row)
            if (!(value is float.init))
                return 21;

    float[257] large_default;
    foreach (value; large_default)
        if (!(value is float.init))
            return 22;

    float[257] repeated = void;
    repeated[] = evaluated_value();
    if (evaluations != 1)
        return 23;
    foreach (value; repeated)
        if (value != -3.5f)
            return 24;

    return 0;
}
