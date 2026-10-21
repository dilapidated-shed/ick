#include "tracker.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
struct header { void *base; size_t size; };
static size_t calls, live_bytes, peak_bytes, allowance = SIZE_MAX;
void mb_tracking_reset(void) { calls = 0; peak_bytes = live_bytes; allowance = SIZE_MAX; }
void mb_fail_after(size_t n) { allowance = n; }
size_t mb_allocations(void) { return calls; }
size_t mb_live(void) { return live_bytes; }
size_t mb_peak(void) { return peak_bytes; }
void *mb_aligned_alloc(size_t alignment, size_t size) {
    if (alignment < _Alignof(max_align_t)) alignment = _Alignof(max_align_t);
    if ((alignment & (alignment-1)) || size > SIZE_MAX-sizeof(struct header)-alignment ||
        size > SIZE_MAX-live_bytes || !allowance) return NULL;
    void *base = malloc(size+sizeof(struct header)+alignment);
    if (!base) return NULL;
    uintptr_t address = ((uintptr_t)base+sizeof(struct header)+alignment-1) & ~(uintptr_t)(alignment-1);
    struct header *h = (struct header *)address-1;
    h->base = base; h->size = size;
    --allowance; ++calls; live_bytes += size;
    if (live_bytes > peak_bytes) peak_bytes = live_bytes;
    return (void *)address;
}
void *mb_malloc(size_t size) { return mb_aligned_alloc(_Alignof(max_align_t), size); }
void *mb_calloc(size_t n, size_t size) {
    if (size && n > SIZE_MAX/size) return NULL;
    void *p = mb_malloc(n*size);
    if (p) memset(p, 0, n*size);
    return p;
}
void mb_free(void *p) {
    if (p) { struct header *h = (struct header *)p-1; live_bytes -= h->size; free(h->base); }
}
void *mb_realloc(void *p, size_t size) {
    if (!p) return mb_malloc(size);
    if (!size) { mb_free(p); return NULL; }
    struct header *h = (struct header *)p-1;
    void *next = mb_malloc(size);
    if (!next) return NULL;
    memcpy(next, p, size < h->size ? size : h->size); mb_free(p); return next;
}
