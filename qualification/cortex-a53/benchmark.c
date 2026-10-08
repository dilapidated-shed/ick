#define _POSIX_C_SOURCE 200809L
#include "kernels.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/utsname.h>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
typedef void (*render_function)(float *, float, float);
static float images[2][3 * PIXELS];
static uint64_t nanoseconds(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) exit(20);
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
static uint64_t image_digest(const float *image)
{
    uint64_t digest = UINT64_C(14695981039346656037);
    for (unsigned index = 0; index < 3 * PIXELS; ++index) {
        uint32_t word; memcpy(&word, &image[index], 4);
        for (unsigned byte = 0; byte < 4; ++byte) {
            digest ^= (word >> (8 * byte)) & 255u;
            digest *= UINT64_C(1099511628211);
        }
    }
    return digest;
}
int main(int argc, char **argv)
{
    char executable[4096], paths[2][4096];
    if (argc != 1) { fputs("benchmark (uses libraries beside executable)\n", stderr); return 21; }
    (void)argv;
    ssize_t length = readlink("/proc/self/exe", executable, sizeof executable - 1);
    if (length <= 0 || (size_t)length >= sizeof executable - 1) return 26;
    executable[length] = '\0';
    char *slash = strrchr(executable, '/');
    if (!slash) return 26;
    *slash = '\0';
    for (unsigned mode = 0; mode < 2; ++mode) {
        int written = snprintf(paths[mode], sizeof paths[mode], "%s/%s/libkernels.so",
                               executable, mode ? "cortex-a53" : "generic");
        if (written < 0 || (size_t)written >= sizeof paths[mode]) return 26;
    }
#ifdef __ANDROID__
    char property[PROP_VALUE_MAX];
    if (__system_property_get("ro.product.model", property) <= 0 ||
        strcmp(property, "Miro C67")) { fputs("FAIL requires physical Miro C67\n", stderr); return 27; }
    puts("receipt_kind\tphysical-device-candidate");
    const char *properties[] = {"ro.product.model", "ro.build.fingerprint",
        "ro.build.version.sdk", "ro.product.cpu.abi", "ro.product.cpu.abilist",
        "ro.product.cpu.abilist32", "ro.product.cpu.abilist64"};
    for (unsigned index = 0; index < sizeof properties / sizeof properties[0]; ++index) {
        int found = __system_property_get(properties[index], property);
        printf("%s\t%s\n", properties[index], found > 0 ? property : "UNKNOWN");
    }
    struct utsname identity;
    if (uname(&identity)) return 28;
    printf("kernel\t%s %s %s\npage_size\t%ld\n", identity.sysname,
           identity.release, identity.machine, sysconf(_SC_PAGESIZE));
#else
    puts("receipt_kind\thost-only-NOT-physical-evidence");
#endif
    render_function render[2];
    for (unsigned mode = 0; mode < 2; ++mode) {
        void *library = dlopen(paths[mode], RTLD_NOW | RTLD_LOCAL);
        if (!library) { fputs(dlerror(), stderr); return 22; }
        void *symbol = dlsym(library, "volume_kernel");
        if (!symbol) return 23;
        _Static_assert(sizeof symbol == sizeof render[mode], "POSIX function pointer");
        memcpy(&render[mode], &symbol, sizeof symbol);
        render[mode](images[mode], 0.75f, 0.875f);
        if (image_digest(images[mode]) != UINT64_C(0x433c7e24606b1dbd)) return 24;
    }
    /* Same driver, alternating AB/BA order, 3 warmups and 31 measured pairs.
       Eight full frames per sample. No emulation timings are retained by CI. */
    puts("trial\torder\tmode\tframes\tnanoseconds\tlast_frame_hash");
    for (int trial = -3; trial < 31; ++trial) {
        uint64_t hashes[2];
        for (unsigned order = 0; order < 2; ++order) {
            unsigned mode = ((unsigned)(trial + 3) + order) & 1u;
            uint64_t start = nanoseconds();
            for (unsigned frame = 0; frame < 8; ++frame)
                render[mode](images[mode], 0.75f + (float)frame * 0.03125f, 0.875f);
            uint64_t elapsed = nanoseconds() - start;
            hashes[mode] = image_digest(images[mode]);
            if (trial >= 0)
                printf("%d\t%u\t%s\t8\t%llu\t%016llx\n", trial, order,
                       mode ? "cortex-a53" : "generic", (unsigned long long)elapsed,
                       (unsigned long long)hashes[mode]);
        }
        if (hashes[0] != hashes[1] || memcmp(images[0], images[1], sizeof images[0])) return 25;
    }
    return 0;
}
