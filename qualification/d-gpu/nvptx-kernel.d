module nvptx_probe;

import gcc.attributes : attribute;

@attribute("gpu_kernel")
extern(C) void ick_gpu_probe(int* values, uint count)
{
    if (count != 0)
        values[0] += 1;
}
