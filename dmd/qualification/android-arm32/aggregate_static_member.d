module aggregate_static_member;

struct AggregateLayout
{
    int left;
    bool present;
    long wide;

    pragma(mangle, "aggregate_static_add")
    static int add(int first, int second)
    {
        return first + second;
    }
}
