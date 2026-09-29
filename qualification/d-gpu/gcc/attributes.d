module gcc.attributes;

private struct Attribute(A...)
{
    A arguments;
}

@system
auto attribute(A...)(A arguments)
    if (A.length > 0 && is(A[0] == string))
{
    return Attribute!A(arguments);
}
