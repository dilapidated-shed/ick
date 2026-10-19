#define MB05_WITH_GMP
#include "providers.h"
#include <stdlib.h>
#include <string.h>

#if GMP_NAIL_BITS != 0 || (GMP_NUMB_BITS != 32 && GMP_NUMB_BITS != 64)
#error "MB05 supports only explicitly qualified 32/64-bit no-nail GMP builds"
#endif

static void pack(mp_limb_t *out, const uint32_t *in, size_t count) {
    for (size_t i = 0; i < count; ++i) {
#if GMP_NUMB_BITS == 64
#ifdef MB05_DROP_HIGH_HALF
        if (i % 2) continue; /* Deliberate repacking defect, test builds only. */
#endif
        out[i/2] |= (mp_limb_t)in[i] << (32*(i%2));
#else
        out[i] = in[i];
#endif
    }
}

void mb05_gmp_destroy(struct mb05_gmp *context) {
    free(context->left); free(context->right); free(context->product);
    memset(context, 0, sizeof(*context));
}

int mb05_gmp_prepare(struct mb05_gmp *context, const uint32_t *a, size_t na,
                     const uint32_t *b, size_t nb, int square) {
    if (!context) return 1;
    memset(context, 0, sizeof(*context));
    if (!a || !b || !na || !nb || na > MB05_MAX_LIMBS || nb > MB05_MAX_LIMBS ||
        (square != 0 && square != 1) || mp_bits_per_limb != GMP_LIMB_BITS) return 1;
    if (square && (na != nb || memcmp(a, b, na*sizeof(*a)))) return 1;
    size_t factor = GMP_NUMB_BITS / 32;
    size_t left_count = (na+factor-1)/factor, right_count = (nb+factor-1)/factor;
    context->left = calloc(left_count, sizeof(mp_limb_t));
    context->right = calloc(right_count, sizeof(mp_limb_t));
    context->product = calloc(left_count+right_count, sizeof(mp_limb_t));
    if (!context->left || !context->right || !context->product) {
        mb05_gmp_destroy(context);
        return 2;
    }
    pack(context->left, a, na); pack(context->right, b, nb);
    /* Trim high zeros deliberately; retain one native limb for zero. */
    while (left_count > 1 && !context->left[left_count-1]) --left_count;
    while (right_count > 1 && !context->right[right_count-1]) --right_count;
    context->left_count = left_count; context->right_count = right_count;
    context->output_count = na+nb; context->square = square;
    if (!square && left_count < right_count) {
        mp_limb_t *swap = context->left; context->left = context->right; context->right = swap;
        context->left_count = right_count; context->right_count = left_count;
    }
    return 0;
}

int mb05_gmp_run(void *opaque) {
    struct mb05_gmp *context = opaque;
    if (!context || !context->left || !context->right || !context->product) return 1;
    if (context->square) mpn_sqr(context->product, context->left, (mp_size_t)context->left_count);
    else (void)mpn_mul(context->product, context->left, (mp_size_t)context->left_count,
                     context->right, (mp_size_t)context->right_count);
    return 0;
}

int mb05_gmp_export(const struct mb05_gmp *context, uint32_t *out) {
    if (!context || !context->product || !out) return 1;
    size_t native_count = context->left_count + context->right_count;
    for (size_t i = 0; i < context->output_count; ++i) {
#if GMP_NUMB_BITS == 64
        out[i] = i/2 < native_count ? (uint32_t)(context->product[i/2] >> (32*(i%2))) : 0;
#else
        out[i] = i < native_count ? context->product[i] : 0;
#endif
    }
    return 0;
}

static int adapter(const uint32_t *a, size_t na, const uint32_t *b, size_t nb, uint32_t *out, int square) {
    if (!out) return 1;
    struct mb05_gmp context;
    int status = mb05_gmp_prepare(&context, a, na, b, nb, square);
    if (!status) status = mb05_gmp_run(&context);
    if (!status) status = mb05_gmp_export(&context, out);
    mb05_gmp_destroy(&context);
    return status;
}

int mb05_gmp32(const uint32_t *a, size_t na, const uint32_t *b, size_t nb, uint32_t *out) {
    return adapter(a, na, b, nb, out, 0);
}
int mb05_gmp_square32(const uint32_t *a, size_t na, const uint32_t *b, size_t nb, uint32_t *out) {
    return adapter(a, na, b, nb, out, 1);
}

#ifdef MB05_EXPORT_CANDIDATE
int mul_candidate(const uint32_t *a, size_t na, const uint32_t *b, size_t nb, uint32_t *out) {
    return mb05_gmp32(a, na, b, nb, out);
}
#endif
