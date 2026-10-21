#ifdef MB_WITH_GMP
#define MB05_WITH_GMP
#endif
#include "../providers/providers.h"
#include "../timing/engine.h"
#include "../memory/tracker.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef __linux__
#include <sys/resource.h>
#endif

extern int mul_schoolbook(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);
typedef int (*provider_fn)(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);
struct request {
    size_t na, nb; uint32_t *a, *b, *saved_a, *saved_b, *expected, *out;
#ifdef MB_WITH_GMP
    struct mb05_gmp native;
#endif
};
struct state { struct request *requests; size_t count, index, calls; int rotate, reused, mixed; provider_fn provider; };
static const uint32_t guard = UINT32_C(0x9137cafe);
static size_t fresh_output_allocations;
static uint32_t *fresh_output(size_t words) {
    uint32_t *output=malloc(4*words);
    if (output) ++fresh_output_allocations;
    return output;
}
static int invoke(void *opaque) {
    struct state *s = opaque;
    struct request *r = &s->requests[s->index];
    (void)r;
    int status = 0;
#ifndef MB_MUTANT_SKIP_CALL
#ifndef MB_UNINSTRUMENTED
    ++s->calls;
#endif
#ifndef MB_MUTANT_CACHED
#ifdef MB_MIXED_FAIL
    if (s->mixed && s->index==3) return 3;
#endif
#ifdef MB_MIXED_DELAY
    if (s->mixed && s->index%8==3) {
        struct timespec delay={0,20000000};
        while (nanosleep(&delay,&delay)) if (errno!=EINTR) return 3;
    }
#endif
#ifdef MB_WITH_GMP
    if (s->reused) status=mb05_gmp_run(&r->native);
    else
#endif
    status = s->provider(r->a, r->na, r->b, r->nb, r->out);
#endif
#ifdef MB_MUTANT_CARRY
    r->out[r->na+r->nb-1] ^= 1;
#endif
#endif
    if (s->rotate) {
#ifdef MB_SINGLE_OPERAND
        s->index=0;
#else
        s->index = (s->index+1)%s->count;
#endif
    }
    return status;
}
static int verify(const struct request *r) {
    return memcmp(r->a,r->saved_a,4*r->na) || memcmp(r->b,r->saved_b,4*r->nb) ||
        r->out[r->na+r->nb] != guard || memcmp(r->out,r->expected,4*(r->na+r->nb));
}
static int number(const char *s, size_t *out) {
    char *end; errno=0;
    if (!*s || *s=='-' || *s=='+') return 1;
    uintmax_t n = strtoumax(s,&end,10);
    if (errno || *end || n>SIZE_MAX) return 1;
    *out=(size_t)n; return 0;
}
static void release(struct request *r) {
#ifdef MB_WITH_GMP
    mb05_gmp_destroy(&r->native);
#endif
    free(r->a); free(r->b); free(r->saved_a); free(r->saved_b); free(r->expected); free(r->out);
}
static void emit_row(size_t trial,size_t index,struct request *rows,const struct mb_sample *sample,
                     size_t calls,uint64_t pre_ns,size_t touched) {
    struct request *r=&rows[index];
#ifdef MB_DROP_RESPONSE
    if (index==1) return;
#endif
    size_t response=index;
#ifdef MB_REORDER_RESPONSE
    if (index<2) response=index^1;
#endif
    const uint32_t *product=r->out;
#ifdef MB_STALE_RESPONSE
    if (index && rows[index-1].na+rows[index-1].nb==r->na+r->nb) product=rows[index-1].out;
#endif
    printf("%zu\t%zu\t%" PRIu64 "\t%zu\t%zu\t%" PRIu64 "\t%zu\t%zu\t%zu\t%zu\t",trial,response,sample->elapsed_ns,sample->repetitions,calls,pre_ns,touched,mb_allocations(),mb_live(),mb_peak());
    for (size_t word=r->na+r->nb;word>0;--word) printf("%08" PRIx32,product[word-1]);
    putchar('\n');
}
int main(int argc, char **argv) {
    size_t trials, cap, batch, budget, eviction;
    if ((argc!=8 && argc!=9) || number(argv[3],&trials) || number(argv[4],&cap) || number(argv[5],&batch) ||
        number(argv[6],&budget) || number(argv[7],&eviction) || !trials || trials>20 || !cap || cap>65536 ||
        !batch || batch>64 || budget>16777216 || budget<4096 || eviction>budget) return 2;
    const char *mode=argv[1];
    int pooled=!strcmp(mode,"rotating-pool");
    int mixed=!strcmp(mode,"mixed"), rotating=!strcmp(mode,"rotating") || pooled;
    int throughput=!strcmp(mode,"mixed-throughput");
    int first=!strcmp(mode,"first-touch"), evict=!strcmp(mode,"eviction-preconditioned");
    if (strcmp(mode,"hot") && !mixed && !throughput && !rotating && !first && !evict && strcmp(mode,"profile")) return 2;
    if ((evict && !eviction) || (!evict && eviction)) return 2;
    const char *workspace=argc==9 ? argv[8] : "fresh";
    int reused=!strcmp(workspace,"reused-native");
    if ((!reused && strcmp(workspace,"fresh")) || (reused && (first || evict))) return 2;
    provider_fn provider=NULL;
    if (!strcmp(argv[2],"schoolbook")) provider=mul_schoolbook;
    if (!strcmp(argv[2],"karatsuba32-bounded")) provider=mb05_karatsuba32;
#ifdef MB_WITH_GMP
    if (!strcmp(argv[2],"gmp-mpn-mul")) provider=mb05_gmp32;
    if (!strcmp(argv[2],"gmp-mpn-sqr")) provider=mb05_gmp_square32;
#endif
    if (!provider) return 2;
    if (reused && strcmp(argv[2],"gmp-mpn-mul") && strcmp(argv[2],"gmp-mpn-sqr")) return 2;
    size_t count=0, used=1024*sizeof(struct request)+eviction, scratch=64*MB05_MAX_LIMBS;
    int failed=0;
    if (used>budget || scratch>budget-used) return 2;
    used+=scratch;
    struct request *rows=calloc(1024,sizeof(*rows));
    if (!rows) return 2;
    while (count<1024) {
        size_t na,nb;
        int scanned=scanf("%zu %zu",&na,&nb);
        if (scanned==EOF) break;
        if (scanned!=2 || !na || !nb || na>MB05_MAX_LIMBS || nb>MB05_MAX_LIMBS) { failed=2; break; }
        size_t charge=16*(na+nb)+4; /* snapshots, expected, output; fixed descriptor pool above */
        if (reused) charge+=8*(na+nb)+16; /* three packed native arrays, including odd-word padding */
        if (charge>budget-used) { failed=2; break; }
        used+=charge;
        struct request *r=&rows[count++]; r->na=na; r->nb=nb;
        r->a=calloc(na,4); r->b=calloc(nb,4); r->saved_a=calloc(na,4); r->saved_b=calloc(nb,4);
        r->expected=calloc(na+nb,4); r->out=calloc(na+nb+1,4);
        if (!r->a || !r->b || !r->saved_a || !r->saved_b || !r->expected || !r->out) { failed=2; break; }
        for (size_t i=0;i<na;++i) if (scanf("%" SCNx32,&r->a[i])!=1) failed=2;
        for (size_t i=0;i<nb;++i) if (scanf("%" SCNx32,&r->b[i])!=1) failed=2;
        if (failed) break;
        memcpy(r->saved_a,r->a,4*na); memcpy(r->saved_b,r->b,4*nb);
        if (mul_schoolbook(r->a,na,r->b,nb,r->expected)) { failed=2; break; }
        r->out[na+nb]=guard;
#ifdef MB_WITH_GMP
#ifdef MB_WORKSPACE_FAIL
        if (reused) mb_fail_after(1);
#endif
        if (reused && mb05_gmp_prepare(&r->native,r->a,na,r->b,nb,!strcmp(argv[2],"gmp-mpn-sqr"))) { failed=2; break; }
#endif
    }
    if (count==1024) { int c; do { c=getchar(); } while (c==' ' || c=='\n' || c=='\t' || c=='\r'); if (c!=EOF) failed=2; }
    unsigned char *sweep=NULL;
    if (!failed && eviction) { sweep=calloc(eviction,1); if (!sweep) failed=2; }
    if (!count) failed=2;
    struct state state={rows,count,0,0,rotating || throughput,reused,mixed || throughput,provider};
#ifdef MB_UNINSTRUMENTED
    fputs("measurement\tuninstrumented\n",stderr);
#else
    fputs("measurement\tcall-counted\n",stderr);
#endif
    fprintf(stderr,"workspace\t%s\n",workspace);
    if (!failed) puts("trial\trequest\telapsed_ns\trepetitions\tcalls\tprecondition_ns\tprecondition_bytes\tallocations\tlive_bytes\tpeak_bytes\tproduct_hex");
    for (size_t trial=0;trial<trials && !failed;++trial) {
        uint64_t batch_start=0; size_t in_batch=0;
        for (size_t index=0;index<count && !failed;++index) {
            struct request *r=&rows[index]; struct mb_sample sample; size_t repetitions=1;
            if (throughput) {
                repetitions=count-index<batch ? count-index : batch;
                for (size_t j=index;j<index+repetitions;++j) {
                    memset(rows[j].out,0xa5,4*(rows[j].na+rows[j].nb));
                    rows[j].out[rows[j].na+rows[j].nb]=guard;
                }
                mb_tracking_reset(); state.index=index; state.calls=0;
                if (mb_batch(invoke,&state,mb_monotonic,NULL,repetitions,&sample)) { failed=3; break; }
#ifndef MB_UNINSTRUMENTED
                if (state.calls!=repetitions) { failed=3; break; }
#endif
                for (size_t j=index;j<index+repetitions;++j) {
#ifdef MB_WITH_GMP
                    if (reused && mb05_gmp_export(&rows[j].native,rows[j].out)) failed=3;
#endif
                    if (verify(&rows[j])) failed=3;
                }
                if (failed) break;
                uint64_t reported_ns=sample.elapsed_ns;
#ifdef MB_BATCH_TIME_MISMATCH
                reported_ns^=1;
#endif
                size_t reported_count=repetitions;
#ifdef MB_BATCH_COUNT_MISMATCH
                ++reported_count;
#endif
                fprintf(stderr,"kernel_batch\t%zu\t%zu\t%zu\t%" PRIu64 "\n",trial,index,reported_count,reported_ns);
                for (size_t j=index;j<index+repetitions;++j) {
                    /* Each response references this shared batch sample, not request latency. */
                    emit_row(trial,j,rows,&sample,state.calls,0,0);
#ifdef MB_DUPLICATE_RESPONSE
                    emit_row(trial,j,rows,&sample,state.calls,0,0);
#endif
                }
                index+=repetitions-1;
                continue;
            }
            uint64_t pre_start=0,pre_end=0; size_t touched=0;
            if (mixed && !in_batch && mb_monotonic(NULL,&batch_start)) { failed=3; break; }
            if (!mixed && !first && !evict && strcmp(mode,"profile")) {
                struct mb_calibration calibration; state.index=index; state.calls=0;
                for (size_t warmup=0;warmup<2;++warmup) if (invoke(&state)) failed=3;
                if (failed) break;
                state.index=index; state.calls=0;
                fprintf(stderr,"warmup\t%zu\t%zu\t2\n",trial,index);
                if (mb_calibrate(invoke,&state,mb_monotonic,NULL,100000,cap,2000000,&calibration)) { failed=3; break; }
                repetitions=calibration.sample.repetitions;
                if (rotating && repetitions<count) repetitions=count;
                fprintf(stderr,"calibration\t%zu\t%zu\t%d\t%d\n",trial,index,calibration.target_met,calibration.cap_hit);
            }
            if (first) {
                size_t before=fresh_output_allocations;
#ifndef MB_REUSED_FRESH
                free(r->out); r->out=fresh_output(r->na+r->nb+1);
#else
                (void)fresh_output;
#endif
                if (!r->out) { failed=2; break; }
                r->out[r->na+r->nb]=guard;
                fprintf(stderr,"output_allocation\t%zu\t%zu\t%zu\n",trial,index,fresh_output_allocations-before);
            } else {
                size_t begin=rotating ? 0 : index, end=rotating ? count : index+1;
                for (size_t j=begin;j<end;++j) { memset(rows[j].out,0xa5,4*(rows[j].na+rows[j].nb)); rows[j].out[rows[j].na+rows[j].nb]=guard; }
            }
            if (evict) {
                if (mb_monotonic(NULL,&pre_start)) { failed=3; break; }
#ifndef MB_MUTANT_SKIP_PRECONDITION
                for (size_t j=0;j<eviction;j+=64) { volatile unsigned char *p=sweep+j; *p=(unsigned char)(*p+1); ++touched; }
#endif
                if (mb_monotonic(NULL,&pre_end)) { failed=3; break; }
            }
            mb_tracking_reset(); state.index=index; state.calls=0;
            if (mb_batch(invoke,&state,mb_monotonic,NULL,repetitions,&sample)) { failed=3; break; }
#ifndef MB_UNINSTRUMENTED
            if (state.calls!=repetitions) { failed=3; break; }
#endif
#ifdef MB_WITH_GMP
            if (reused) {
                size_t begin=rotating ? 0 : index, end=rotating ? count : index+1;
                for (size_t j=begin;j<end;++j) if (mb05_gmp_export(&rows[j].native,rows[j].out)) failed=3;
            }
#endif
            if (rotating) { for (size_t j=0;j<count;++j) if (verify(&rows[j])) failed=3; }
            else if (verify(r)) failed=3;
            if (failed) break;
            if (pooled) fprintf(stderr,"pool_batch\t%zu\t%zu\t%zu\t%" PRIu64 "\n",trial,count,repetitions,sample.elapsed_ns);
            size_t response_end=pooled ? count : index+1;
            for (size_t response=index;response<response_end;++response) {
                emit_row(trial,response,rows,&sample,state.calls,pre_end-pre_start,touched);
#ifdef MB_DUPLICATE_RESPONSE
                emit_row(trial,response,rows,&sample,state.calls,pre_end-pre_start,touched);
#endif
            }
            if (pooled) index=count-1;
            if (mixed && (++in_batch==batch || index+1==count)) {
                uint64_t end; if (mb_monotonic(NULL,&end)) { failed=3; break; }
                fprintf(stderr,"batch\t%zu\t%zu\t%zu\t%" PRIu64 "\n",trial,index+1-in_batch,in_batch,end-batch_start); in_batch=0;
            }
        }
    }
    for (size_t i=0;i<count;++i) release(&rows[i]);
    free(rows); free(sweep);
    fprintf(stderr,"final_live_bytes\t%zu\n",mb_live());
    if (mb_live()) failed=3;
#ifdef __linux__
    struct rusage usage;
    if (getrusage(RUSAGE_SELF,&usage) || usage.ru_maxrss<0 || (uint64_t)usage.ru_maxrss>UINT64_MAX/1024) failed=3;
    else {
#ifdef MB_RSS_WRONG_UNIT
        uint64_t rss=(uint64_t)usage.ru_maxrss;
#else
        uint64_t rss=(uint64_t)usage.ru_maxrss*1024;
#endif
        fprintf(stderr,"rss_max\t%ld\tKiB\t%" PRIu64 "\tbytes\n",usage.ru_maxrss,rss);
    }
#else
    fputs("rss_max\tNOT_AVAILABLE\n",stderr);
#endif
    if (failed) fprintf(stderr,"workload failed: %d\n",failed);
    return failed;
}
