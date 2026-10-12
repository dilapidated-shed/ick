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
typedef struct {
  unsigned precision,source_length,target_length,alpha;
  unsigned gaussian_radius,error_radius,neumann_terms;
} resampling_parameters;
typedef struct resampling_plan resampling_plan;
typedef struct {
  uint64_t coefficient_count,allocated_limb_bytes,allocated_descriptor_bytes,ram_products,ram_additions;
  uint64_t selection_records,line_calls;
  scalar_work scalar;
} resampling_work;
exact_status resampling_admit(unsigned p,unsigned s,unsigned t,unsigned alpha,
                               uint64_t coefficient_budget,resampling_parameters *);
/* Fresh null plan pointer; owned plan is immutable except measured counters.
 * Calls require initialized, disjoint caller arrays of disk-grid Gaussian
 * records and preserve every output on failure. Calls are not concurrent. */
exact_status resampling_prepare(const resampling_parameters *,uint64_t coefficient_budget,resampling_plan **);
void resampling_clear(resampling_plan *);
exact_status resampling_A(resampling_plan *,const exact_gaussian *,size_t input_length,exact_gaussian *,size_t output_length);
exact_status resampling_B0(resampling_plan *,const exact_gaussian *,size_t input_length,exact_gaussian *,size_t output_length);
exact_status resampling_receipt(const resampling_plan *,resampling_parameters *,resampling_work *);
unsigned resampling_nearest(const resampling_parameters *,unsigned source_index);
#endif
