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
static int set_line_input(exact_gaussian *values,unsigned length,unsigned example,unsigned precision) {
  for (unsigned index=0;index<length;++index) {
    int64_t real=example<length ? index==example : (int64_t)((index*7+example*3)%3)-1;
    int64_t imaginary=example<length ? 0 : (int64_t)((index*11+example*5)%3)-1;
    size_t scale=example<length ? 0 : example==length ? 1 : precision;
    if (exact_set(&values[index].real,real,scale) || exact_set(&values[index].imaginary,imaginary,scale)) return 0;
  }
  return 1;
}
static int line_checks(unsigned precision,unsigned source,unsigned target,unsigned alpha) {
  resampling_parameters parameters;
  exact_status status=resampling_admit(precision,source,target,alpha,65536,&parameters);
  if (status!=EXACT_OK) { fprintf(stderr,"parameter refusal p=%u s=%u t=%u alpha=%u status=%u\n",precision,source,target,alpha,status); return 0; }
  resampling_plan *plan=NULL; status=resampling_prepare(&parameters,65536,&plan);
  if (status!=EXACT_OK) { fprintf(stderr,"preparation refusal p=%u status=%u\n",precision,status); return 0; }
  int success=0; exact_gaussian input[64]={0},output[64]={0};
  for (unsigned index=0;index<64;++index)
    if (exact_init(&input[index].real,16) || exact_init(&input[index].imaginary,16)
        || exact_init(&output[index].real,16) || exact_init(&output[index].imaginary,16)) goto done;
  printf("line-parameter\t%u\t%u\t%u\t%u\t%u\t%u\t%u\n",precision,source,target,alpha,
         parameters.gaussian_radius,parameters.error_radius,parameters.neumann_terms);
  for (unsigned index=0;index<source;++index)
    printf("nearest\t%u\t%u\t%u\t%u\t%u\n",precision,source,target,index,resampling_nearest(&parameters,index));
  for (unsigned direction=0;direction<2;++direction) {
    unsigned input_length=direction ? target : source,output_length=direction ? source : target;
    for (unsigned example=0;example<input_length+2;++example) {
      if (!set_line_input(input,input_length,example,precision)) goto done;
      status=direction ? resampling_B0(plan,input,input_length,output,output_length)
                       : resampling_A(plan,input,input_length,output,output_length);
      if (status!=EXACT_OK) { fprintf(stderr,"line refusal p=%u direction=%u case=%u status=%u\n",precision,direction,example,status); goto done; }
      for (unsigned index=0;index<output_length;++index) {
        printf("line\t%s\t%u\t%u\t%u\t%u\t%u\t%u\t",direction ? "B0" : "A",precision,source,target,alpha,example,index);
        if (!emit(&output[index].real,precision)) goto done;
        putchar('\t'); if (!emit(&output[index].imaginary,precision)) goto done;
        putchar('\n');
      }
    }
  }
  if (resampling_A(plan,input,source,output,target-1)!=EXACT_INVALID
      || resampling_A(plan,input,source,input,target)!=EXACT_INVALID) goto done;
  if (exact_set(&input[0].real,2,0) || resampling_A(plan,input,source,output,target)!=EXACT_INVALID) goto done;
  resampling_work work;
  if (resampling_receipt(plan,&parameters,&work)) goto done;
  fprintf(stderr,"line-work\tp=%u\ts=%u\tt=%u\talpha=%u\tcoefficients=%llu\tallocated_limb_bytes=%llu\tallocated_descriptor_bytes=%llu\tram_products=%llu\tram_additions=%llu\tselection_records=%llu\tline_calls=%llu\tseries_terms=%llu\tpeak_scalar_limb_bytes=%llu\n",
          precision,source,target,alpha,(unsigned long long)work.coefficient_count,(unsigned long long)work.allocated_limb_bytes,
          (unsigned long long)work.allocated_descriptor_bytes,(unsigned long long)work.ram_products,(unsigned long long)work.ram_additions,
          (unsigned long long)work.selection_records,(unsigned long long)work.line_calls,
          (unsigned long long)work.scalar.series_terms,(unsigned long long)work.scalar.peak_limb_bytes);
  success=1;
done:
  for (unsigned index=0;index<64;++index) {
    exact_clear(&input[index].real); exact_clear(&input[index].imaginary);
    exact_clear(&output[index].real); exact_clear(&output[index].imaginary);
  }
  resampling_clear(plan); return success;
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
  if (!line_checks(101,12,17,4) || !line_checks(128,15,23,5) || !line_checks(256,31,38,6)) return 50;
  exact_clear(&output.real); exact_clear(&output.imaginary); return ferror(stdout) ? 49 : 0;
}
