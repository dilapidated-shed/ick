#ifndef MB05_PROVIDERS_H
#define MB05_PROVIDERS_H
#include <stddef.h>
#include <stdint.h>

/* Bounded benchmark controls, not a production bigint API. Nonzero lengths,
 * aligned arrays, output capacity na+nb; output must not overlap either input.
 * Inputs may alias one another. All output words, including high zeroes, are
 * written. No output is promised after a nonzero return. */
#define MB05_MAX_LIMBS 2048
int mb05_karatsuba32(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);

#ifdef MB05_WITH_GMP
#include <gmp.h>
struct mb05_gmp {
    mp_limb_t *left, *right, *product;
    size_t left_count, right_count, output_count;
    int square;
};
/* A prepared context owns separate native arrays. Preparation, packing,
 * trimming, export and destruction must stay outside native-kernel timing. */
int mb05_gmp_prepare(struct mb05_gmp *, const uint32_t *, size_t,
                     const uint32_t *, size_t, int);
int mb05_gmp_run(void *);
int mb05_gmp_export(const struct mb05_gmp *, uint32_t *);
void mb05_gmp_destroy(struct mb05_gmp *);
int mb05_gmp32(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);
int mb05_gmp_square32(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);
#endif
#endif
