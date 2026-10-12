#include "composition.h"
#include <stdio.h>
int main(void) {
  composition_parameters parameters; recovery_certificate certificate;
  if (composition_admit(REDUCED_ALGEBRA,&parameters,&certificate)) return 60;
  printf("parameters\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\n",
    parameters.precision,parameters.radix_bits,parameters.input_bit_limit,parameters.axes,parameters.ring_length,
    parameters.source[0],parameters.source[1],parameters.target[0],parameters.target[1],parameters.prefix[0],parameters.prefix[1],
    parameters.inverse_prefix[0],parameters.inverse_prefix[1],parameters.source_product,parameters.target_product,
    parameters.source_scale_bits,parameters.prime_candidates,parameters.trial_divisions);
  printf("recovery\t%u\t%u\t%u\t%u\t%u\t%u\t",certificate.precision,certificate.strict_half_unit,certificate.coefficient_limit,
    certificate.chirp_error_units,certificate.source_error_base,certificate.source_error_shift);
  for (unsigned index=8;index>0;--index) printf("%08x",certificate.error_units[index-1]);
  putchar('\n');
  printf("published-refusal\t%u\n",composition_admit(PUBLISHED_FIXED,&parameters,&certificate));
  return ferror(stdout) ? 61 : 0;
}
