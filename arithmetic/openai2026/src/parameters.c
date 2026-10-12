#include "composition.h"
#include "exact_internal.h"
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static int prime(unsigned candidate,unsigned *divisions) {
  if (candidate<2) return 0;
  for (unsigned divisor=2;divisor*divisor<=candidate;++divisor) {
    ++*divisions; if (!(candidate%divisor)) return 0;
  }
  return 1;
}
static unsigned modular_inverse(unsigned value,unsigned modulus) {
  for (unsigned inverse=1;inverse<modulus;++inverse) if ((value*inverse)%modulus==1) return inverse;
  return 0;
}
exact_status composition_admit(composition_profile profile,composition_parameters *out,recovery_certificate *certificate) {
  if (!out || !certificate || exact_overlap(out,sizeof(*out),certificate,sizeof(*certificate)) || profile!=REDUCED_ALGEBRA) return EXACT_INVALID;
  composition_parameters parameters={0}; recovery_certificate recovery={0};
  parameters.precision=256; parameters.radix_bits=3; parameters.input_bit_limit=8;
  parameters.axes=2; parameters.ring_length=8; parameters.target[0]=4; parameters.target[1]=8; parameters.alpha=6;
  parameters.source_product=1; parameters.target_product=1;
  for (unsigned axis=0;axis<2;++axis) {
    resampling_parameters line;
    for (unsigned candidate=parameters.target[axis]-1;candidate>=2;--candidate) {
      ++parameters.prime_candidates;
      if (!prime(candidate,&parameters.trial_divisions) || (axis && candidate==parameters.source[0])) continue;
      if (resampling_admit(parameters.precision,candidate,parameters.target[axis],parameters.alpha,65536,&line)==EXACT_OK) {
        parameters.source[axis]=candidate; break;
      }
    }
    if (!parameters.source[axis]) return EXACT_INVALID;
    parameters.prefix[axis]=parameters.source_product;
    parameters.inverse_prefix[axis]=modular_inverse(parameters.prefix[axis],parameters.source[axis]);
    if (!parameters.inverse_prefix[axis]) return EXACT_INVALID;
    parameters.source_product*=parameters.source[axis]; parameters.target_product*=parameters.target[axis];
  }
  parameters.outer_records=parameters.target_product/parameters.ring_length;
  parameters.source_scale_bits=2*parameters.axes*parameters.alpha*parameters.alpha;
  unsigned digits=(parameters.input_bit_limit+parameters.radix_bits-1)/parameters.radix_bits;
  if (2*digits-2>=parameters.source_product) return EXACT_INVALID;
  recovery.precision=parameters.precision;
  recovery.coefficient_limit=digits*((1u<<parameters.radix_bits)-1)*((1u<<parameters.radix_bits)-1);
  if (recovery.coefficient_limit>=(1u<<(3*parameters.radix_bits))) return EXACT_INVALID;
  /* The scaled half-kernel chirp has error <1024 ulps, derived separately.
   * Both ordered tensor maps contribute d p^2, then 2^gamma amplifies them.
   * Both distinct S factors and the radix scale enter final recovery. */
  recovery.chirp_error_units=1024;
  recovery.source_error_base=2*parameters.axes*parameters.precision*parameters.precision+recovery.chirp_error_units;
  recovery.source_error_shift=parameters.source_scale_bits;
  exact_dyadic source_error={0},final_error={0},factor={0},temporary={0},bound={0}; exact_status status=EXACT_OK;
  TRY(exact_init(&source_error,8)); TRY(exact_init(&final_error,8)); TRY(exact_init(&factor,8));
  TRY(exact_init(&temporary,8)); TRY(exact_init(&bound,8));
  TRY(exact_set(&source_error,recovery.source_error_base,0)); TRY(exact_shift(&source_error,&source_error,recovery.source_error_shift));
  TRY(exact_set(&factor,3,0)); TRY(short_mul_schoolbook(&temporary,&source_error,&factor));
  TRY(exact_set(&factor,2,0)); TRY(exact_add(&temporary,&temporary,&factor));
  uint64_t scale=(UINT64_C(1)<<(2*parameters.radix_bits+4))*parameters.source_product*parameters.source_product;
  TRY(exact_set(&factor,(int64_t)scale,0)); TRY(short_mul_schoolbook(&final_error,&temporary,&factor));
  TRY(exact_set(&bound,1,0)); TRY(exact_shift(&bound,&bound,parameters.precision-1));
  int order; TRY(exact_compare(&order,&final_error,&bound));
  if (order>=0 || final_error.length>8) { status=EXACT_INVALID; goto done; }
  recovery.strict_half_unit=1; recovery.error_words=(unsigned)final_error.length;
  memcpy(recovery.error_units,final_error.limbs,final_error.length*sizeof(uint32_t));
  *out=parameters; *certificate=recovery;
done:
  exact_clear(&source_error); exact_clear(&final_error); exact_clear(&factor); exact_clear(&temporary); exact_clear(&bound); return status;
}
