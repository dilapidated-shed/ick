#include "../../timing/engine.h"
#include <inttypes.h>
#include <stdio.h>
int main(void) {
    uint32_t marker=1; struct timespec resolution; uint64_t ns;
    if (clock_getres(CLOCK_MONOTONIC,&resolution) || mb_timespec_ns(&resolution,&ns)) return 2;
    printf("uint32_bytes\t%zu\nsize_t_bytes\t%zu\npointer_bytes\t%zu\nbyte_order\t%s\nclock_resolution_ns\t%" PRIu64 "\n",sizeof(uint32_t),sizeof(size_t),sizeof(void *),*(unsigned char *)&marker ? "little" : "big",ns);
    return 0;
}
