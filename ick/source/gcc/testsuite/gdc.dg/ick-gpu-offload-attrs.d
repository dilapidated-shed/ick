// { dg-do compile }
// { dg-options "-fopenmp -fdump-tree-gimple" }

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

@attribute("gpu_kernel")
extern(C) void launchEntry(int* value)
{
    *value += 1;
}

@attribute("gpu") int notAFunction; // { dg-warning ".gpu. attribute ignored" }

// gpu contributes one "omp declare target".
// gpu_only and gpu_kernel each also contribute "... nohost".
// { dg-final { scan-tree-dump-times "omp declare target nohost" 2 "gimple" } }
// { dg-final { scan-tree-dump-times "omp declare target" 5 "gimple" } }
