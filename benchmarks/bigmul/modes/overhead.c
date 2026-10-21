#include "../timing/engine.h"
#include <inttypes.h>
#include <stdio.h>
struct state { size_t calls; volatile unsigned sink; };
static int operation(void *opaque) {
    struct state *state=opaque;
#ifndef MB_UNINSTRUMENTED
    ++state->calls;
#endif
    state->sink^=1;
    return 0;
}
int main(void) {
    puts("kind\ttrial\trepetitions\telapsed_ns\tcalls");
    for (size_t trial=0;trial<20;++trial) {
        uint64_t start,end;
        if (mb_monotonic(NULL,&start) || mb_monotonic(NULL,&end) || end<start) return 2;
        printf("clock-pair\t%zu\t1\t%" PRIu64 "\t0\n",trial,end-start);
        for (size_t reps=1;reps<=4096;reps*=4096) {
            struct state state={0,0}; struct mb_sample sample;
            if (mb_batch(operation,&state,mb_monotonic,NULL,reps,&sample)) return 2;
#ifndef MB_UNINSTRUMENTED
            if (state.calls!=reps) return 3;
#endif
            printf("callback-volatile\t%zu\t%zu\t%" PRIu64 "\t%zu\n",trial,reps,sample.elapsed_ns,state.calls);
        }
    }
    return 0;
}
