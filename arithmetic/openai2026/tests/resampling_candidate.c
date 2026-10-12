#include "error_bounds.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int emit(const exact_dyadic *value,unsigned precision) {
  uint8_t bytes[48]; size_t width=(precision+9)/8;
  if (width>sizeof(bytes) || exact_serialize(value,precision,bytes,width)) return 0;
  for (size_t index=0;index<width;++index) printf("%02x",bytes[index]);
  return 1;
}
int main(void) {
  certified_scalar_context refused;
  if (certified_scalar_init(&refused,100)!=EXACT_INVALID || refused.pi.lower.limbs
      || certified_scalar_init(&refused,257)!=EXACT_INVALID || refused.pi.lower.limbs) return 39;
  const unsigned precisions[]={101,128,256};
  const uint32_t numerators[]={0,1,1,7,3,200,101,UINT32_MAX,4,9,0};
  const uint32_t denominators[]={1,1,3,13,2,1,1,1000000,1,4,1};
  const unsigned powers[]={0,0,0,0,0,0,0,0,30,70,0};
  const uint32_t root_denominators[]={2,3,4,5,7,17,65537,UINT32_MAX};
  exact_gaussian output={0};
  if (exact_init(&output.real,16) || exact_init(&output.imaginary,16)) return 40;
  for (unsigned profile=0;profile<3;++profile) {
    unsigned precision=precisions[profile]; certified_scalar_context context;
    exact_status status=certified_scalar_init(&context,precision);
    if (status!=EXACT_OK) { fprintf(stderr,"constant refusal p=%u status=%u\n",precision,status); return 41; }
    const exact_dyadic *constants[]={&context.pi.lower,&context.pi.upper,&context.log_two.lower,&context.log_two.upper};
    for (unsigned constant=0;constant<4;++constant) {
      printf("constant\t%u\t%u\t",precision,constant);
      if (!emit(constants[constant],context.working_precision)) return 42;
      putchar('\n');
    }
    for (unsigned example=0;example<11;++example) {
      scalar_certificate certificate;
      status=certified_exponential(&context,numerators[example],denominators[example],example>=8,powers[example],&output.real,&certificate);
      if (status!=EXACT_OK) { fprintf(stderr,"exponential refusal p=%u case=%u status=%u\n",precision,example,status); return 43; }
      printf("exponential\t%u\t%u\t%u\t%u\t%u\t",precision,numerators[example],denominators[example],example>=8,powers[example]);
      if (!emit(&output.real,precision)) return 44;
      printf("\t%u\t%u\t%u\n",certificate.series_terms,certificate.range_shifts,certificate.early_zero);
    }
    for (unsigned denominator=0;denominator<8;++denominator) {
      uint32_t k=root_denominators[denominator],js[]={0,1,k/2,k-1};
      for (unsigned example=0;example<4;++example) {
        scalar_certificate certificate;
        status=certified_root(&context,js[example],k,&output,&certificate);
        if (status!=EXACT_OK) { fprintf(stderr,"root refusal p=%u j=%u k=%u status=%u\n",precision,js[example],k,status); return 45; }
        printf("root\t%u\t%u\t%u\t",precision,js[example],k);
        if (!emit(&output.real,precision)) return 46;
        putchar('\t'); if (!emit(&output.imaginary,precision)) return 46;
        printf("\t%u\t%u\n",certificate.series_terms,certificate.range_shifts);
      }
    }
    if (certified_exponential(&context,1,0,0,0,&output.real,&(scalar_certificate){0})!=EXACT_INVALID
        || certified_exponential(&context,1,1,1,0,&output.real,&(scalar_certificate){0})!=EXACT_INVALID
        || certified_root(&context,2,2,&output,&(scalar_certificate){0})!=EXACT_INVALID) return 47;
    if (certified_exponential(&context,1,1,0,0,&output.real,(scalar_certificate *)context.pi.lower.limbs)!=EXACT_INVALID) return 47;
    exact_gaussian empty={0};
    if (certified_root(&context,1,4,&empty,&(scalar_certificate){0})!=EXACT_CAPACITY
        || empty.real.limbs || empty.imaginary.limbs || empty.real.length || empty.imaginary.length) return 47;
    fprintf(stderr,"scalar-work\tp=%u\tpi_terms=%u\tlog_terms=%u\tproducts=%llu\tdivisions=%llu\tseries_terms=%llu\tallocations=%llu\tpeak_limb_bytes=%llu\tlive_limb_bytes=%llu\n",
            precision,context.pi_terms,context.log_terms,(unsigned long long)context.work.products,
            (unsigned long long)context.work.divisions,(unsigned long long)context.work.series_terms,
            (unsigned long long)context.work.allocations,(unsigned long long)context.work.peak_limb_bytes,
            (unsigned long long)context.work.live_limb_bytes);
    if (context.work.live_limb_bytes!=4*32*sizeof(uint32_t)) return 48;
    certified_scalar_clear(&context);
  }
  exact_clear(&output.real); exact_clear(&output.imaginary); return ferror(stdout) ? 49 : 0;
}
