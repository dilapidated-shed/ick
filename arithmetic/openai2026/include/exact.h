#ifndef OPENAI2026_EXACT_H
#define OPENAI2026_EXACT_H
#include <stddef.h>
#include <stdint.h>

typedef enum { EXACT_OK, EXACT_CAPACITY, EXACT_ALLOCATION, EXACT_INVALID } exact_status;
typedef struct {
  uint32_t *limbs;
  size_t length, capacity, binary_scale;
  int sign;
} exact_dyadic;
typedef struct { exact_dyadic real, imaginary; } exact_gaussian;

/* Initialization requires a fresh record. Failure produces canonical zero;
 * clear releases only its original independently owned initialized storage. */
exact_status exact_init(exact_dyadic *, size_t capacity);
void exact_clear(exact_dyadic *);
exact_status exact_set(exact_dyadic *, int64_t numerator, size_t binary_scale);
exact_status exact_copy(exact_dyadic *, const exact_dyadic *);
exact_status exact_compare(int *order, const exact_dyadic *, const exact_dyadic *);
exact_status exact_add(exact_dyadic *, const exact_dyadic *, const exact_dyadic *);
exact_status exact_subtract(exact_dyadic *, const exact_dyadic *, const exact_dyadic *);
exact_status exact_shift(exact_dyadic *, const exact_dyadic *, size_t left_bits);
exact_status exact_half(exact_dyadic *, const exact_dyadic *);
exact_status exact_truncate(exact_dyadic *, const exact_dyadic *, size_t binary_scale);
exact_status exact_serialize(const exact_dyadic *, size_t binary_scale,
                             uint8_t *output, size_t width);

enum { SCALAR_TRIPLES = 20, SCALAR_SIDES = 200, SCALAR_CENTRAL = 6,
       SCALAR_FIELDS = 247 };
typedef struct {
  exact_gaussian source[SCALAR_TRIPLES], target[SCALAR_TRIPLES];
  exact_gaussian side[SCALAR_SIDES], central[SCALAR_CENTRAL], star;
} scalar_network;
exact_status scalar_init(scalar_network *, size_t capacity);
void scalar_clear(scalar_network *);
exact_gaussian *scalar_field(scalar_network *, size_t index);
const exact_gaussian *scalar_const_field(const scalar_network *, size_t index);
exact_status scalar_execute(scalar_network *, int inverse);
/* Observer snapshots are emitted after each completed schedule step. A failed
 * observation aborts the transaction but retains already-emitted evidence. */
typedef exact_status (*scalar_observer)(void *, unsigned step, const scalar_network *);
exact_status scalar_execute_observed(scalar_network *, int inverse, scalar_observer, void *);
exact_status scalar_signed_swap(scalar_network *);
#endif
