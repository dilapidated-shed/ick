#include "providers.h"
#include <stdlib.h>
#include <string.h>

extern int mul_schoolbook(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);

static int compare(const uint32_t *a, const uint32_t *b, size_t n) {
    while (n) {
        --n;
        if (a[n] != b[n]) return a[n] > b[n] ? 1 : -1;
    }
    return 0;
}

static int subtract(uint32_t *a, size_t na, const uint32_t *b, size_t nb) {
    uint64_t borrow = 0;
    for (size_t i = 0; i < na; ++i) {
        uint64_t sub = (i < nb ? b[i] : 0) + borrow;
        uint32_t word = a[i];
        a[i] = (uint32_t)((uint64_t)word - sub);
        borrow = (uint64_t)word < sub;
    }
    return borrow != 0;
}

static int add_at(uint32_t *out, size_t count, const uint32_t *a, size_t n, size_t offset) {
    uint64_t carry = 0;
    size_t i = 0;
    for (; i < n || carry; ++i) {
        if (offset + i >= count) return 1;
        uint64_t sum = (uint64_t)out[offset+i] + (i < n ? a[i] : 0) + carry;
        out[offset+i] = (uint32_t)sum;
        carry = sum >> 32;
    }
    return 0;
}

static void difference(uint32_t *out, const uint32_t *a, const uint32_t *b, size_t n, int sign) {
    memcpy(out, sign < 0 ? b : a, n * sizeof(*out));
    (void)subtract(out, n, sign < 0 ? a : b, n);
}

/* Equal power-of-two widths. Difference form keeps recursive operands at
 * exactly half width; the cross term alone needs an extra carry word. */
static int recursive(const uint32_t *a, const uint32_t *b, size_t n, uint32_t *out) {
    if (n <= 16) return mul_schoolbook(a, n, b, n, out);
    size_t half = n / 2;
    uint32_t *storage = calloc(5*n + 1, sizeof(*storage));
    if (!storage) return 2;
    uint32_t *low = storage, *high = low+n, *delta = high+n;
    uint32_t *left_delta = delta+n, *right_delta = left_delta+half;
    uint32_t *cross = right_delta+half;
    int left_sign = compare(a+half, a, half), right_sign = compare(b+half, b, half);
    difference(left_delta, a+half, a, half, left_sign);
    difference(right_delta, b+half, b, half, right_sign);
    int failed = recursive(a, b, half, low) || recursive(a+half, b+half, half, high)
              || recursive(left_delta, right_delta, half, delta);
    if (!failed) {
        failed = add_at(cross, n+1, low, n, 0) || add_at(cross, n+1, high, n, 0);
        if (left_sign * right_sign < 0) failed |= add_at(cross, n+1, delta, n, 0);
        else failed |= subtract(cross, n+1, delta, n);
        memset(out, 0, 2*n*sizeof(*out));
        failed |= add_at(out, 2*n, low, n, 0) || add_at(out, 2*n, high, n, n)
               || add_at(out, 2*n, cross, n+1, half);
    }
    free(storage);
    return failed;
}

int mb05_karatsuba32(const uint32_t *a, size_t na, const uint32_t *b, size_t nb, uint32_t *out) {
    if (!a || !b || !out || !na || !nb || na > MB05_MAX_LIMBS || nb > MB05_MAX_LIMBS) return 1;
    size_t n = 1, count = na+nb;
    while (n < na || n < nb) n *= 2;
    uint32_t *storage = calloc(4*n, sizeof(*storage));
    if (!storage) return 2;
    memcpy(storage, a, na*sizeof(*a));
    memcpy(storage+n, b, nb*sizeof(*b));
    int status = recursive(storage, storage+n, n, storage+2*n);
    if (!status) memcpy(out, storage+2*n, count*sizeof(*out));
    free(storage);
    return status;
}

#ifdef MB05_EXPORT_CANDIDATE
int mul_candidate(const uint32_t *a, size_t na, const uint32_t *b, size_t nb, uint32_t *out) {
    return mb05_karatsuba32(a, na, b, nb, out);
}
#endif
