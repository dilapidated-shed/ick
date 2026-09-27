// { dg-do compile }

import gcc.attributes : attribute;

@attribute("gpu_kernel")
int notVoid()
{
    return 1;
}

// { dg-error ".gpu_kernel. attribute requires a void return type" "" { target *-*-* } 5 }
