#include "numerical_internal.h"
#include <stdlib.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static void accumulate(numerical_trace *out,const numerical_trace *in) {
  out->motif_calls+=in->motif_calls; out->layer_batches+=in->layer_batches;
  out->layout_coefficient_moves+=in->layout_coefficient_moves; out->monomial_coefficient_moves+=in->monomial_coefficient_moves;
  out->rounding_sites+=in->rounding_sites;
  out->prepared_matrix_entries=in->prepared_matrix_entries;
  out->persistent_limb_bytes=in->persistent_limb_bytes; out->persistent_descriptor_bytes=in->persistent_descriptor_bytes;
}
exact_status numerical_convolution_observed(synthetic_plan *plan,const exact_gaussian *first,const exact_gaussian *second,
                                    exact_gaussian *out,const short_mul_provider *provider,numerical_trace *trace,
                                    numerical_convolution_observer observer,void *context) {
  if (!plan || !provider || !provider->identity || !provider->multiply || !trace) return EXACT_INVALID;
  const synthetic_descriptor *descriptor=&plan->descriptor; unsigned ring=descriptor->ring_length,records=descriptor->records,p=descriptor->precision;
  size_t length=(size_t)records*ring; uint64_t error=2*(uint64_t)records*records*(3*descriptor->rounds+1)*(3*descriptor->rounds+1);
  /* Strict error <1/2 with rho=1/2; squared certificate avoids irrational arithmetic. */
  if (p<32 && 4*error>=(UINT64_C(1)<<(2*p))) return EXACT_INVALID;
  exact_status status=numerical_array_contract(first,second,out,length); if (status!=EXACT_OK) return status;
  if (!numerical_trace_contract(trace,first,second,out,length) || exact_overlap(trace,sizeof(*trace),plan,sizeof(*plan))
      || exact_overlap(trace,sizeof(*trace),provider,sizeof(*provider))) return EXACT_INVALID;
  for (size_t index=0;index<length;++index) {
    status=numerical_radius(&first[index],p,1); if (status!=EXACT_OK) return status;
    status=numerical_radius(&second[index],p,1); if (status!=EXACT_OK) return status;
  }
  exact_gaussian *left=NULL,*right=NULL,*product=NULL,*result=NULL;
  numerical_trace receipt={0},stage={0}; unsigned logarithm=0; for (unsigned value=records;value>1;value>>=1) ++logarithm;
  TRY(numerical_values(&left,length,plan->capacity)); TRY(numerical_values(&right,length,plan->capacity));
  TRY(numerical_values(&product,length,plan->capacity)); TRY(numerical_values(&result,length,plan->capacity));
  TRY(synthetic_transform(plan,first,left,0,&stage,NULL,NULL)); accumulate(&receipt,&stage);
  if (observer) TRY(observer(context,"left",0,left,length,NULL));
  TRY(synthetic_transform(plan,second,right,0,&stage,NULL,NULL)); accumulate(&receipt,&stage);
  if (observer) TRY(observer(context,"right",0,right,length,NULL));
  for (unsigned address=0;address<records;++address) {
    short_mul_trace short_receipt={0};
    TRY(packed_product(&left[address*ring],&right[address*ring],ring,p,&product[address*ring],provider,&short_receipt));
    if (short_receipt.calls!=4 || short_receipt.identity!=provider->identity) { status=EXACT_INVALID; goto done; }
    receipt.short_calls+=short_receipt.calls;
    if (observer) TRY(observer(context,"pointwise",address,&product[address*ring],ring,&short_receipt));
  }
  TRY(synthetic_transform(plan,product,result,1,&stage,NULL,NULL)); accumulate(&receipt,&stage);
  if (observer) TRY(observer(context,"opposite",0,result,length,NULL));
  for (size_t index=0;index<length;++index) {
#ifdef MUTANT_SCALE
    TRY(exact_shift(&result[index].real,&result[index].real,logarithm+1)); TRY(exact_shift(&result[index].imaginary,&result[index].imaginary,logarithm+1));
#else
    TRY(exact_shift(&result[index].real,&result[index].real,logarithm)); TRY(exact_shift(&result[index].imaginary,&result[index].imaginary,logarithm));
#endif
    if (result[index].real.length>out[index].real.capacity || result[index].imaginary.length>out[index].imaginary.capacity) { status=EXACT_CAPACITY; goto done; }
    TRY(numerical_radius(&result[index],p,0));
  }
  if (observer) TRY(observer(context,"scale",0,result,length,NULL));
  for (size_t index=0;index<length;++index) TRY(numerical_copy_value(&out[index],&result[index]));
done:
  receipt.persistent_limb_bytes+=4*length*2*plan->capacity*sizeof(uint32_t);
  receipt.persistent_descriptor_bytes+=4*length*sizeof(exact_gaussian);
  receipt.error_squared_numerator=(unsigned)error; receipt.error_binary_scale=2*p; receipt.output_width=p+2+logarithm; *trace=receipt;
  numerical_clear_values(left,length); numerical_clear_values(right,length); numerical_clear_values(product,length); numerical_clear_values(result,length); return status;
}
exact_status numerical_convolution(synthetic_plan *plan,const exact_gaussian *first,const exact_gaussian *second,
                                    exact_gaussian *out,const short_mul_provider *provider,numerical_trace *trace) {
  return numerical_convolution_observed(plan,first,second,out,provider,trace,NULL,NULL);
}
