#ifndef OPENAI2026_NUMERICAL_H
#define OPENAI2026_NUMERICAL_H
#include "exact.h"
#include "network.h"
#include "layout.h"

typedef struct {
  const char *identity;
  uint64_t calls,validation_products;
  size_t left_bits[4],right_bits[4],result_bits[4];
} short_mul_trace;
typedef exact_status (*short_mul_function)(exact_dyadic *,const exact_dyadic *,const exact_dyadic *);
typedef struct { const char *identity; short_mul_function multiply; } short_mul_provider;
typedef exact_status (*numerical_product_observer)(void *,const exact_gaussian *,unsigned length);
/* Conventional provider, explicitly limited to the reduced model. Arguments
 * are unsigned integer magnitudes; the packed-product caller restores signs. */
exact_status short_mul_schoolbook(exact_dyadic *,const exact_dyadic *,const exact_dyadic *);
exact_status packed_product(const exact_gaussian *,const exact_gaussian *,unsigned length,unsigned precision,
                              exact_gaussian *,const short_mul_provider *,short_mul_trace *);
exact_status packed_product_observed(const exact_gaussian *,const exact_gaussian *,unsigned length,unsigned precision,
                                       exact_gaussian *,const short_mul_provider *,short_mul_trace *,
                                       numerical_product_observer,void *observer_context);
typedef struct phase_layer_plan phase_layer_plan;
/* Exact C or (-i) Z C Z on one child; no grid rounding. */
exact_status numerical_C_child(exact_gaussian output[2],const exact_gaussian input[2],int inverse);
typedef struct {
  uint64_t reserved_roles,padded_rows,frame_calls,encoding_additions;
  uint64_t prepared_matrix_entries,allocated_limb_bytes,allocated_descriptor_bytes;
  unsigned fractional_guard_bits,magnitude_guard_bits;
} phase_layer_trace;
/* Reduced exact quotient: y_i=(e_i tensor t_0 tensor t_0).x in F2, i=0..3.
 * Full h=4 frame operators preserve this function space. X inputs other than
 * role zero must vanish; Y and all auxiliaries may be arbitrary. Unused y
 * coordinates are constant, and the complete selected range has 2^axes slots.
 * This executes the accepted motif; it is not a dense/tape-profile admission. */
exact_status phase_layer_prepare(unsigned precision,unsigned axes,uint64_t record_budget,phase_layer_plan **);
void phase_layer_clear(phase_layer_plan *);
exact_status phase_layer_apply(phase_layer_plan *,const exact_gaussian *,unsigned input_rows,
                                 exact_gaussian *,phase_layer_trace *);
#endif
