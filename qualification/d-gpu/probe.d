module probe;

import gcc.attributes : attribute;

@attribute("gpu")
int twice(int value)
{
    return value * 2;
}

@attribute("gpu_only")
int deviceOnly(int value)
{
    return value + 1;
}
