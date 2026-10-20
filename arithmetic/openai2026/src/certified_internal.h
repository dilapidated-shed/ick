#ifndef OPENAI2026_CERTIFIED_INTERNAL_H
#define OPENAI2026_CERTIFIED_INTERNAL_H
#include "error_bounds.h"
#include "exact_internal.h"
enum { CERTIFIED_LIMBS=32 };
exact_status bound_init(certified_scalar_context *,directed_interval *);
void bound_clear(certified_scalar_context *,directed_interval *);
exact_status bound_copy(directed_interval *,const directed_interval *);
exact_status bound_integer(directed_interval *,int64_t);
exact_status bound_add(certified_scalar_context *,directed_interval *,const directed_interval *,const directed_interval *,int subtract);
exact_status bound_product(certified_scalar_context *,directed_interval *,const directed_interval *,const directed_interval *);
exact_status bound_scale(certified_scalar_context *,directed_interval *,const directed_interval *,uint32_t numerator,uint32_t denominator);
exact_status bound_divide_power(certified_scalar_context *,directed_interval *,const directed_interval *,unsigned power);
exact_status scalar_point_product(certified_scalar_context *,exact_dyadic *,const exact_dyadic *,const exact_dyadic *);
exact_status scalar_round(certified_scalar_context *,exact_dyadic *,const exact_dyadic *,unsigned scale,int upward);
exact_status scalar_divide(certified_scalar_context *,exact_dyadic *,const exact_dyadic *,uint32_t divisor,int upward);
#endif
