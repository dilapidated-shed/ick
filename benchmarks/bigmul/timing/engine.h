#ifndef MB_TIMING_ENGINE_H
#define MB_TIMING_ENGINE_H
#include <stdint.h>
#include <stddef.h>
#include <time.h>
typedef int (*mb_operation)(void *);
typedef int (*mb_timer)(void *, uint64_t *);
struct mb_sample { uint64_t elapsed_ns; size_t repetitions; };
struct mb_calibration {
    struct mb_sample sample;
    int target_met;
    int cap_hit;
    uint64_t accumulated_ns;
};
int mb_timespec_ns(const struct timespec *, uint64_t *);
int mb_monotonic(void *, uint64_t *);
int mb_batch(mb_operation, void *, mb_timer, void *, size_t, struct mb_sample *);
int mb_calibrate(mb_operation, void *, mb_timer, void *, uint64_t, size_t,
                 uint64_t, struct mb_calibration *);
#endif
