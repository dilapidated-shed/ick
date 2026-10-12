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
#endif
