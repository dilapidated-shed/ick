#define MB05_WITH_GMP
#include "providers.h"
#include "../timing/engine.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct request { uint32_t *left, *right, *output; size_t na, nb; int square; };
static int adapted(void *opaque) {
    struct request *request = opaque;
    return request->square ? mb05_gmp_square32(request->left, request->na, request->right, request->nb, request->output)
                           : mb05_gmp32(request->left, request->na, request->right, request->nb, request->output);
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--metadata")) {
        printf("{\"gmp_version\":\"%s\",\"header_version\":\"%d.%d.%d\","
               "\"numb_bits\":%d,\"nail_bits\":%d,\"limb_bytes\":%zu,\"runtime_limb_bits\":%d,"
               "\"internal_algorithm\":\"UNKNOWN\"}\n", gmp_version,
               __GNU_MP_VERSION, __GNU_MP_VERSION_MINOR, __GNU_MP_VERSION_PATCHLEVEL,
               GMP_NUMB_BITS, GMP_NAIL_BITS, sizeof(mp_limb_t), mp_bits_per_limb);
        return 0;
    }
    if (argc != 3 || (strcmp(argv[1], "native") && strcmp(argv[1], "adapter32")) ||
        (strcmp(argv[2], "multiply") && strcmp(argv[2], "square"))) return 2;
    int native = !strcmp(argv[1], "native"), square = !strcmp(argv[2], "square");
    puts("case\tmode\toperation\ttrial\telapsed_ns\trepetitions\tproduct_hex");
    size_t na, nb, index = 0;
    for (;;) {
        int read = scanf("%zu %zu", &na, &nb);
        if (read == EOF) return ferror(stdin) ? 2 : 0;
        if (read != 2 || !na || !nb || na > MB05_MAX_LIMBS || nb > MB05_MAX_LIMBS) return 2;
        struct request request = {NULL, NULL, NULL, na, nb, square};
        request.left = calloc(na, sizeof(uint32_t)); request.right = calloc(nb, sizeof(uint32_t));
        request.output = calloc(na+nb, sizeof(uint32_t));
        if (!request.left || !request.right || !request.output) return 3;
        for (size_t i = 0; i < na; ++i) if (scanf("%" SCNu32, &request.left[i]) != 1) return 2;
        for (size_t i = 0; i < nb; ++i) if (scanf("%" SCNu32, &request.right[i]) != 1) return 2;
        struct mb05_gmp context;
        if (mb05_gmp_prepare(&context, request.left, na, request.right, nb, square)) return 3;
        for (int trial = 0; trial < 3; ++trial) {
            struct mb_sample sample;
            /* Fixed short diagnostic batches: no calibrated speed claim. */
            if (mb_batch(native ? mb05_gmp_run : adapted, native ? (void *)&context : (void *)&request,
                         mb_monotonic, NULL, 8, &sample)) return 4;
            if (native && mb05_gmp_export(&context, request.output)) return 4;
            printf("%zu\t%s\t%s\t%d\t%" PRIu64 "\t%zu\t", index, argv[1], argv[2],
                   trial, sample.elapsed_ns, sample.repetitions);
            for (size_t i = na+nb; i; --i) printf("%08" PRIx32, request.output[i-1]);
            putchar('\n');
        }
        mb05_gmp_destroy(&context);
        free(request.left); free(request.right); free(request.output);
        ++index;
    }
}
