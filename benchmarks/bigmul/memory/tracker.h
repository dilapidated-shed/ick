#ifndef MB_TRACKER_H
#define MB_TRACKER_H
#include <stddef.h>
void *mb_malloc(size_t);
void *mb_calloc(size_t, size_t);
void *mb_aligned_alloc(size_t, size_t);
void *mb_realloc(void *, size_t);
void mb_free(void *);
void mb_tracking_reset(void);
void mb_fail_after(size_t);
size_t mb_allocations(void);
size_t mb_live(void);
size_t mb_peak(void);
#endif
