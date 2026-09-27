// { dg-do compile { target nvptx*-*-* } }
// { dg-options "-O2 -fno-druntime" }
// { dg-final { scan-assembler-times {\.visible[ 	]+\.entry[ 	]+ick_gpu_entry} 1 } }
// { dg-final { scan-assembler {st\.global} } }

import gcc.attributes : attribute;

@attribute("gpu_kernel")
extern(C) void ick_gpu_entry(int* values, uint count)
{
    if (count != 0)
        values[0] += 1;
}
