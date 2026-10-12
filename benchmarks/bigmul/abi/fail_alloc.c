/* Host GNU-linker fixture only. Interpose calls from the tested object. */
#include <stddef.h>
#include <stdlib.h>
extern void *__real_malloc(size_t);
extern void *__real_calloc(size_t,size_t);
static size_t allocation_calls;
static int fail_now(void) {
    const char *configured=getenv("MB_FAIL_ALLOCATION");
    return configured && ++allocation_calls==(size_t)strtoul(configured,NULL,10);
}
void *__wrap_malloc(size_t bytes) { return fail_now() ? NULL : __real_malloc(bytes); }
void *__wrap_calloc(size_t count,size_t bytes) { return fail_now() ? NULL : __real_calloc(count,bytes); }
