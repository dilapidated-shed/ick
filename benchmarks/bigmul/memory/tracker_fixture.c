#include "tracker.h"
#include <stdint.h>
#include <stdio.h>
int main(void) {
    mb_tracking_reset();
    void *a = mb_malloc(32), *b = mb_calloc(8, 8);
    if (!a || !b || mb_live()!=96) return 1;
    void *next = mb_realloc(a, 128);
    if (!next || mb_live()!=192 || mb_peak()!=224) return 2;
    a = next; mb_fail_after(0);
    if (mb_realloc(a, 256) || mb_live()!=192) return 3;
    mb_fail_after(SIZE_MAX);
    next=mb_realloc(a,16);
    if (!next || mb_live()!=80 || mb_peak()!=224) return 5;
    a=next; mb_free(a); mb_free(b);
    a = mb_aligned_alloc(64, 64);
    if (!a || (uintptr_t)a%64) return 4;
#ifndef MB_TRACKER_LEAK
    mb_free(a);
#endif
    if (mb_live()) { fputs("tracked leak\n", stderr); return 6; }
    a=mb_malloc(96);
    if (!a) return 8;
    mb_fail_after(0);
    if (mb_realloc(a,256) || mb_live()!=96) return 9;
#ifndef MB_TRACKER_ERROR_LEAK
    mb_free(a);
#endif
    if (mb_live()) { fputs("error cleanup leak\n",stderr); return 7; }
    puts("live=0 peak=224 aligned=64 failure_preserved=1 shrink=1 error_cleanup=1"); return 0;
}
