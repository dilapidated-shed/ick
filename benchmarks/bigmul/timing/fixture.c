#include "engine.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int mul_schoolbook(const uint32_t*,size_t,const uint32_t*,size_t,uint32_t*);
struct fixture { uint32_t a[2], b[2], out[4]; size_t calls; int control; };
static int operation(void *opaque) {
    struct fixture *fixture = opaque;
    ++fixture->calls; /* fixture instrumentation, included in this timing */
#ifdef ELIDE_ARITHMETIC
    return 0;
#else
    if (fixture->control) {
        memcpy(fixture->out, fixture->a, sizeof(fixture->a));
        fixture->out[2] = fixture->out[3] = 0;
        return 0;
    }
    return mul_schoolbook(fixture->a,2,fixture->b,2,fixture->out);
#endif
}
static int cpu_ns(uint64_t *result) {
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now)) return 1;
    return mb_timespec_ns(&now, result);
}
int main(int argc, char **argv) {
    if (argc != 6) return 2;
    struct fixture fixture = {{0,0},{0,0},{0,0,0,0},0,0};
    for (int i=0;i<4;++i) {
        char *end;
        unsigned long long number = strtoull(argv[i+1],&end,10);
        if (*end || number > UINT32_MAX) return 2;
        if(i<2) fixture.a[i]=(uint32_t)number; else fixture.b[i-2]=(uint32_t)number;
    }
    fixture.control = !strcmp(argv[5],"control");
    struct mb_calibration calibration;
    if (mb_calibrate(operation,&fixture,mb_monotonic,NULL,1000000,65535,50000000,&calibration)) return 3;
    struct timespec resolution;
    uint64_t resolution_ns;
    if (clock_getres(CLOCK_MONOTONIC,&resolution) || mb_timespec_ns(&resolution,&resolution_ns)) return 3;
    puts("trial\twall_ns\tcpu_ns\trepetitions\tresolution_ns\ttarget_met\tcap_hit\tcalls\tcontrol\tout0\tout1\tout2\tout3");
    for (int trial=0;trial<6;++trial) {
        uint64_t cpu_start,cpu_end;
        struct mb_sample sample;
        size_t before=fixture.calls;
        if (cpu_ns(&cpu_start) || mb_batch(operation,&fixture,mb_monotonic,NULL,
            calibration.sample.repetitions,&sample) || cpu_ns(&cpu_end) || cpu_end<cpu_start) return 3;
        printf("%d\t%" PRIu64 "\t%" PRIu64 "\t%zu\t%" PRIu64 "\t%d\t%d\t%zu\t%d",
               trial,sample.elapsed_ns,cpu_end-cpu_start,sample.repetitions,resolution_ns,
               calibration.target_met,calibration.cap_hit,fixture.calls-before,fixture.control);
        for (size_t i=0;i<4;++i) printf("\t%" PRIu32,fixture.out[i]);
        putchar('\n');
    }
    return 0;
}
