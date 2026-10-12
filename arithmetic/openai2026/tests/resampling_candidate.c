#include "error_bounds.h"
#include "certified_internal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

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
/* Verification-only normalized quadratic DFT. The ordered maps do not call it. */
static exact_status direct_fourier(certified_scalar_context *context,const exact_gaussian *input,
                                    unsigned length,exact_gaussian *output) {
  exact_gaussian root={0}; exact_dyadic first={0},second={0},real={0},imaginary={0}; exact_status status=EXACT_OK;
#define CHECK(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
  CHECK(exact_init(&root.real,32)); CHECK(exact_init(&root.imaginary,32));
  CHECK(exact_init(&first,32)); CHECK(exact_init(&second,32)); CHECK(exact_init(&real,32)); CHECK(exact_init(&imaginary,32));
  for (unsigned frequency=0;frequency<length;++frequency) {
    CHECK(exact_set(&output[frequency].real,0,0)); CHECK(exact_set(&output[frequency].imaginary,0,0));
    for (unsigned index=0;index<length;++index) {
      scalar_certificate certificate; unsigned exponent=(length-(index*frequency)%length)%length;
      CHECK(certified_root(context,exponent,length,&root,&certificate));
      CHECK(scalar_point_product(context,&first,&root.real,&input[index].real));
      CHECK(scalar_point_product(context,&second,&root.imaginary,&input[index].imaginary));
      CHECK(exact_subtract(&real,&first,&second)); CHECK(exact_truncate(&real,&real,context->precision));
      CHECK(scalar_point_product(context,&first,&root.real,&input[index].imaginary));
      CHECK(scalar_point_product(context,&second,&root.imaginary,&input[index].real));
      CHECK(exact_add(&imaginary,&first,&second)); CHECK(exact_truncate(&imaginary,&imaginary,context->precision));
      CHECK(exact_add(&output[frequency].real,&output[frequency].real,&real));
      CHECK(exact_add(&output[frequency].imaginary,&output[frequency].imaginary,&imaginary));
    }
    CHECK(scalar_divide(context,&output[frequency].real,&output[frequency].real,length,output[frequency].real.sign<0));
    CHECK(scalar_divide(context,&output[frequency].imaginary,&output[frequency].imaginary,length,output[frequency].imaginary.sign<0));
    CHECK(exact_truncate(&output[frequency].real,&output[frequency].real,context->precision));
    CHECK(exact_truncate(&output[frequency].imaginary,&output[frequency].imaginary,context->precision));
  }
done:
  exact_clear(&root.real); exact_clear(&root.imaginary); exact_clear(&first); exact_clear(&second); exact_clear(&real); exact_clear(&imaginary);
#undef CHECK
  return status;
}
static int identity_check(resampling_plan *plan,const resampling_parameters *parameters,
                            exact_gaussian *input,exact_gaussian *output) {
  unsigned precision=parameters->precision,source=parameters->source_length,target=parameters->target_length,alpha=parameters->alpha;
  exact_gaussian fourier[64]={0},permuted[64]={0},recovered[64]={0}; certified_scalar_context context={0}; int success=0;
  for (unsigned index=0;index<64;++index)
    if (exact_init(&fourier[index].real,16) || exact_init(&fourier[index].imaginary,16)
        || exact_init(&permuted[index].real,16) || exact_init(&permuted[index].imaginary,16)
        || exact_init(&recovered[index].real,16) || exact_init(&recovered[index].imaginary,16)) goto done;
  if (!set_line_input(input,source,source,precision) || resampling_A(plan,input,source,output,target)
      || certified_scalar_init(&context,precision) || direct_fourier(&context,output,target,fourier)) goto done;
  for (unsigned index=0;index<target;++index) {
    unsigned from=(target-(source*index)%target)%target;
    if (exact_copy(&permuted[index].real,&fourier[from].real) || exact_copy(&permuted[index].imaginary,&fourier[from].imaginary)) goto done;
  }
  if (resampling_B0(plan,permuted,target,recovered,source)) goto done;
  for (unsigned index=0;index<source;++index) {
    if (exact_shift(&recovered[index].real,&recovered[index].real,2*alpha*alpha)
        || exact_shift(&recovered[index].imaginary,&recovered[index].imaginary,2*alpha*alpha)) goto done;
    printf("identity\t%u\t%u\t%u\t%u\t%u\t",precision,source,target,alpha,index);
    if (!emit(&recovered[index].real,precision)) goto done;
    putchar('\t'); if (!emit(&recovered[index].imaginary,precision)) goto done;
    putchar('\n');
  }
  fprintf(stderr,"ordered-identity\tp=%u\ts=%u\tt=%u\talpha=%u\tverification-provider=normalized-quadratic-DFT\tpermutations=Ps,Pt\tscale=2^(2alpha^2)\n",precision,source,target,alpha);
  success=1;
done:
  for (unsigned index=0;index<64;++index) {
    exact_clear(&fourier[index].real); exact_clear(&fourier[index].imaginary);
    exact_clear(&permuted[index].real); exact_clear(&permuted[index].imaginary);
    exact_clear(&recovered[index].real); exact_clear(&recovered[index].imaginary);
  }
  certified_scalar_clear(&context); return success;
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
  if (!identity_check(plan,&parameters,input,output)) goto done;
  exact_gaussian insufficient[64]={0};
  if (!set_line_input(input,source,0,precision)
      || resampling_A(plan,input,source,insufficient,target)!=EXACT_CAPACITY) goto done;
  for (unsigned index=0;index<target;++index)
    if (insufficient[index].real.limbs || insufficient[index].imaginary.limbs
        || insufficient[index].real.length || insufficient[index].imaginary.length) goto done;
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
static int tensor_checks(void) {
  resampling_parameters first_parameters,second_parameters;
  resampling_plan *first=NULL,*second=NULL; exact_gaussian *box=NULL; int success=0;
  if (resampling_admit(101,12,17,4,65536,&first_parameters)
      || resampling_admit(101,11,16,4,65536,&second_parameters)
      || resampling_prepare(&first_parameters,65536,&first) || resampling_prepare(&second_parameters,65536,&second)) goto done;
  box=calloc(2052,sizeof(*box)); if (!box) goto done;
  for (size_t index=0;index<2052;++index) if (exact_init(&box[index].real,16) || exact_init(&box[index].imaginary,16)) goto done;
  for (unsigned prefix=0;prefix<2;++prefix) for (unsigned row=0;row<12;++row)
    for (unsigned column=0;column<11;++column) for (unsigned tail=0;tail<3;++tail) {
      size_t address=(((size_t)prefix*18+row)*19+column)*3+tail;
      int64_t real=(int64_t)((prefix*31+row*11+column*7+tail*5)%7)-3;
      int64_t imaginary=(int64_t)((prefix*13+row*17+column*19+tail*23)%11)-5;
      if (exact_set(&box[address].real,real,4) || exact_set(&box[address].imaginary,imaginary,4)) goto done;
    }
  for (unsigned direction=0;direction<2;++direction) {
    exact_status status=resampling_tensor(first,second,(int)direction,2,3,18,19,box,2052);
    if (status!=EXACT_OK) { fprintf(stderr,"tensor refusal direction=%u status=%u\n",direction,status); goto done; }
    for (unsigned prefix=0;prefix<2;++prefix) for (unsigned row=0;row<18;++row)
      for (unsigned column=0;column<19;++column) for (unsigned tail=0;tail<3;++tail) {
        size_t address=(((size_t)prefix*18+row)*19+column)*3+tail;
        printf("tensor\t%s\t101\t%u\t%u\t%u\t%u\t",direction ? "B0A" : "A",prefix,row,column,tail);
        if (!emit(&box[address].real,101)) goto done;
        putchar('\t'); if (!emit(&box[address].imaginary,101)) goto done;
        putchar('\n');
      }
  }
  /* Nonzero padding is outside the admitted source-box contract. */
  if (exact_set(&box[(((size_t)17*19)+18)*3].real,1,0)
      || resampling_tensor(first,second,0,2,3,18,19,box,2052)!=EXACT_INVALID) goto done;
  fprintf(stderr,"tensor-work\tprofiles=12-to-17,11-to-16\tprecision=101\tprefixes=2\tsuffix=3\tbox=18x19\tcaller_records=2052\tpadding=preserved\n");
  success=1;
done:
  if (box) { for (size_t index=0;index<2052;++index) { exact_clear(&box[index].real); exact_clear(&box[index].imaginary); } free(box); }
  resampling_clear(first); resampling_clear(second); return success;
}
int main(void) {
#ifdef MUTANT_ORACLE_BYPASS
  return system("cat \"$SCALAR_ORACLE_OUTPUT\"");
#endif
  certified_scalar_context refused;
  if (certified_scalar_init(&refused,100)!=EXACT_INVALID || refused.pi.lower.limbs
      || certified_scalar_init(&refused,257)!=EXACT_INVALID || refused.pi.lower.limbs) return 39;
  resampling_parameters refused_parameters;
  if (resampling_admit(100,12,17,4,65536,&refused_parameters)!=EXACT_INVALID
      || resampling_admit(128,2,3,4,65536,&refused_parameters)!=EXACT_INVALID
      || resampling_admit(144,2,3,12,65536,&refused_parameters)!=EXACT_INVALID
      || resampling_admit(101,12,18,4,65536,&refused_parameters)!=EXACT_INVALID
      || resampling_admit(101,0,17,4,65536,&refused_parameters)!=EXACT_INVALID
      || resampling_admit(101,17,17,4,65536,&refused_parameters)!=EXACT_INVALID
      || resampling_admit(101,2,65,4,65536,&refused_parameters)!=EXACT_CAPACITY
      || resampling_admit(101,12,17,4,1,&refused_parameters)!=EXACT_CAPACITY) return 39;
  const unsigned precisions[]={101,128,256};
  const uint32_t numerators[]={0,1,1,7,3,200,101,UINT32_MAX,4,9,0};
  const uint32_t denominators[]={1,1,3,13,2,1,1,1000000,1,4,1};
  const unsigned powers[]={0,0,0,0,0,0,0,0,30,70,0};
  const uint32_t root_denominators[]={2,3,4,5,7,17,65537,UINT32_MAX};
  exact_gaussian output={0};
  if (exact_init(&output.real,16) || exact_init(&output.imaginary,16)) return 40;
  for (unsigned profile=0;profile<3;++profile) {
    unsigned precision=precisions[profile]; certified_scalar_context context;
    clock_t constants_started=clock(); if (constants_started==(clock_t)-1) return 41;
    exact_status status=certified_scalar_init(&context,precision);
    clock_t constants_finished=clock(); if (constants_finished==(clock_t)-1) return 41;
    if (status!=EXACT_OK) { fprintf(stderr,"constant refusal p=%u status=%u\n",precision,status); return 41; }
    fprintf(stderr,"constant-generation\tp=%u\tworking_bits=%u\tcpu_ns=%llu\towned_limb_bytes=%llu\tpeak_limb_bytes=%llu\n",
            precision,context.working_precision,(unsigned long long)((uint64_t)(constants_finished-constants_started)*UINT64_C(1000000000)/CLOCKS_PER_SEC),
            (unsigned long long)context.work.live_limb_bytes,(unsigned long long)context.work.peak_limb_bytes);
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
  if (!tensor_checks()) return 51;
  struct rusage usage={0}; if (getrusage(RUSAGE_SELF,&usage)) return 52;
  fprintf(stderr,"host-process\tmaximum_rss_kib=%ld\tmeasurement=Linux-getrusage\n",usage.ru_maxrss);
  exact_clear(&output.real); exact_clear(&output.imaginary); return ferror(stdout) ? 49 : 0;
}
