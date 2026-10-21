#include <stdint.h>
#include <stdio.h>
#include <time.h>
int main(void) {
    uint32_t words[2]={UINT32_C(0x01234567),UINT32_C(0x89abcdef)};
    fputs("limb_wire\t",stdout);
    for (size_t i=0;i<2;++i) for (unsigned j=0;j<4;++j) printf("%02x",(unsigned)((words[i]>>(8*j))&255));
    printf("\nsize_t_bytes\t%zu\npointer_bytes\t%zu\n",sizeof(size_t),sizeof(void *));
#ifdef _AIX
    fputs("native_aix_timer\tUNQUALIFIED\n",stderr); return 2;
#else
    struct timespec resolution;
    if (clock_getres(CLOCK_MONOTONIC,&resolution)) return 2;
    printf("portable_control_clock\tCLOCK_MONOTONIC\nunit\tns\nresolution_seconds\t%ld\nresolution_nanoseconds\t%ld\n",(long)resolution.tv_sec,resolution.tv_nsec);
    return 0;
#endif
}
