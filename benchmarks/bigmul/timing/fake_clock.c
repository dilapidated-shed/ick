#include "engine.h"
#include <stdint.h>
struct clock_fixture { uint64_t time, step; int failure; size_t calls; };
static int timer(void *opaque,uint64_t *value) {
    struct clock_fixture *clock=opaque;
    if(clock->failure) return 1;
    *value=clock->time; clock->time+=clock->step;
    return 0;
}
static int operation(void *opaque) { ++((struct clock_fixture*)opaque)->calls; return 0; }
int main(void) {
    struct clock_fixture clock={0,100,0,0};
    struct mb_calibration calibration;
    if(mb_calibrate(operation,&clock,timer,&clock,200,7,10000,&calibration)) return 1;
    if(calibration.target_met || !calibration.cap_hit || clock.calls!=7 || calibration.accumulated_ns!=300) return 2;
    clock=(struct clock_fixture){0,100,0,0};
    if(mb_calibrate(operation,&clock,timer,&clock,100,7,10000,&calibration) || !calibration.target_met || clock.calls!=1) return 3;
    clock=(struct clock_fixture){0,0,0,0};
    if(!mb_calibrate(operation,&clock,timer,&clock,100,7,10000,&calibration)) return 4;
    clock.failure=1;
    if(!mb_calibrate(operation,&clock,timer,&clock,100,7,10000,&calibration)) return 5;
    if(!mb_calibrate(operation,&clock,timer,&clock,0,7,10000,&calibration)) return 6;
    struct timespec time={2,3}; uint64_t result;
    if(mb_timespec_ns(&time,&result) || result!=UINT64_C(2000000003)) return 7;
    time.tv_nsec=1000000000L;
    if(!mb_timespec_ns(&time,&result)) return 8;
    time.tv_sec=(time_t)(UINT64_MAX/UINT64_C(1000000000)+1); time.tv_nsec=0;
    if(!mb_timespec_ns(&time,&result)) return 9;
    /* An awkward call cap must not replace a large sample with its tiny tail. */
    clock=(struct clock_fixture){0,100,0,0};
    if(mb_calibrate(operation,&clock,timer,&clock,200,4096,10000,&calibration)) return 10;
    if(calibration.target_met || !calibration.cap_hit || clock.calls!=4095 ||
       calibration.sample.repetitions!=2048 || calibration.accumulated_ns!=1200) return 11;
    /* A remaining batch may still grow when the cap is not a power of two. */
    clock=(struct clock_fixture){0,100,0,0};
    if(mb_calibrate(operation,&clock,timer,&clock,200,6,10000,&calibration)) return 12;
    if(calibration.target_met || !calibration.cap_hit || clock.calls!=6 ||
       calibration.sample.repetitions!=3 || calibration.accumulated_ns!=300) return 13;
    clock=(struct clock_fixture){0,100,0,0};
    if(mb_calibrate(operation,&clock,timer,&clock,200,1,10000,&calibration) ||
       !calibration.cap_hit || clock.calls!=1 || calibration.sample.repetitions!=1) return 14;
    return 0;
}
