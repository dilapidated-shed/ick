#include "engine.h"
#include <string.h>

int mb_timespec_ns(const struct timespec *time, uint64_t *result) {
    if (!time || !result || time->tv_sec < 0 || time->tv_nsec < 0 ||
        time->tv_nsec >= 1000000000L) return 1;
    uint64_t seconds = (uint64_t)time->tv_sec;
    if (seconds > (UINT64_MAX - (uint64_t)time->tv_nsec) / UINT64_C(1000000000)) return 1;
    *result = seconds * UINT64_C(1000000000) + (uint64_t)time->tv_nsec;
    return 0;
}
int mb_monotonic(void *unused, uint64_t *value) {
    (void)unused;
    struct timespec time;
    if (clock_gettime(CLOCK_MONOTONIC, &time)) return 1;
    return mb_timespec_ns(&time, value);
}
int mb_batch(mb_operation operation, void *context, mb_timer timer, void *clock,
             size_t repetitions, struct mb_sample *sample) {
    uint64_t start, end;
    if (!operation || !timer || !sample || !repetitions || timer(clock, &start)) return 1;
    for (size_t i = 0; i < repetitions; ++i)
        if (operation(context)) return 2;
    if (timer(clock, &end) || end <= start) return 3;
    sample->elapsed_ns = end - start;
    sample->repetitions = repetitions;
    return 0;
}
int mb_calibrate(mb_operation operation, void *context, mb_timer timer, void *clock,
                 uint64_t target_ns, size_t max_calls, uint64_t max_total_ns,
                 struct mb_calibration *result) {
    if (!result || !target_ns || !max_calls || !max_total_ns) return 1;
    memset(result, 0, sizeof(*result));
    size_t repetitions = 1, total_calls = 0;
    for (;;) {
        int status = mb_batch(operation, context, timer, clock, repetitions, &result->sample);
        if (status) return status;
        total_calls += repetitions;
        if (result->sample.elapsed_ns > UINT64_MAX - result->accumulated_ns) return 4;
        result->accumulated_ns += result->sample.elapsed_ns;
        result->target_met = result->sample.elapsed_ns >= target_ns;
        size_t remaining = max_calls - total_calls;
        /* Keep the largest completed batch when the budget cannot fit another
           batch of that size. A tiny leftover must not become the sample. */
        result->cap_hit = remaining < repetitions || result->accumulated_ns >= max_total_ns;
        if (result->target_met || result->cap_hit) return 0;
        repetitions = repetitions > remaining / 2 ? remaining : repetitions * 2;
    }
}
