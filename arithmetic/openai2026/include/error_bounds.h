#ifndef OPENAI2026_ERROR_BOUNDS_H
#define OPENAI2026_ERROR_BOUNDS_H
#include "exact.h"
#include <stdint.h>

typedef struct { exact_dyadic lower,upper; } directed_interval;
typedef struct {
  uint64_t products,divisions,series_terms,allocations,live_limb_bytes,peak_limb_bytes;
} scalar_work;
typedef struct {
  unsigned precision,working_precision,pi_terms,log_terms;
  directed_interval pi,log_two;
  scalar_work work;
} certified_scalar_context;
typedef struct {
  unsigned precision,working_precision,series_terms,range_shifts;
  unsigned strict_error_units,early_zero;
} scalar_certificate;
/* Fresh context; p=101..256, 64 guard bits, checked 1024-bit workspace.
 * Output buffers retain their contents on failure. Initialized contexts and
 * output storage must be distinct and must not be mutated during a call. */
exact_status certified_scalar_init(certified_scalar_context *, unsigned precision);
void certified_scalar_clear(certified_scalar_context *);
exact_status certified_root(certified_scalar_context *, uint32_t j,uint32_t k,
                              exact_gaussian *,scalar_certificate *);
exact_status certified_exponential(certified_scalar_context *,uint32_t j,uint32_t k,
                                     int positive,unsigned binary_scale,
                                     exact_dyadic *,scalar_certificate *);
#endif
