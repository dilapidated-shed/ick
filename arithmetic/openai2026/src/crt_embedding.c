#include "composition.h"
#include "exact_internal.h"
#include <stdlib.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static exact_dyadic *part(exact_gaussian *value,unsigned imaginary) { return imaginary ? &value->imaginary : &value->real; }
static exact_status copy(exact_gaussian *out,const exact_gaussian *input) {
  exact_status status=exact_copy(&out->real,&input->real);
  return status==EXACT_OK ? exact_copy(&out->imaginary,&input->imaginary) : status;
}
static int parameters_valid(const composition_parameters *parameters) {
  return parameters && parameters->precision==256 && parameters->radix_bits==3 && parameters->input_bit_limit==8
      && parameters->axes==2 && parameters->ring_length==8 && parameters->source[0]==3 && parameters->source[1]==5
      && parameters->target[0]==4 && parameters->target[1]==8 && parameters->prefix[0]==1 && parameters->prefix[1]==3
      && parameters->inverse_prefix[0]==1 && parameters->inverse_prefix[1]==2 && parameters->source_product==15
      && parameters->target_product==32 && parameters->outer_records==4 && parameters->alpha==6 && parameters->source_scale_bits==144;
}
exact_status composition_crt(const composition_parameters *parameters,const exact_gaussian *input,size_t input_length,
                             exact_gaussian *out,size_t output_length,int inverse,composition_trace *trace,
                             composition_observer observer,void *context) {
  if (!parameters_valid(parameters) || !input || !out || !trace || (inverse!=0 && inverse!=1)
      || input_length!=(inverse ? 32 : 15) || output_length!=(inverse ? 15 : 32)
      || exact_overlap(input,input_length*sizeof(*input),out,output_length*sizeof(*out))
      || exact_overlap(trace,sizeof(*trace),input,input_length*sizeof(*input))
      || exact_overlap(trace,sizeof(*trace),out,output_length*sizeof(*out))
      || exact_overlap(trace,sizeof(*trace),parameters,sizeof(*parameters))) return EXACT_INVALID;
  size_t capacity=0;
  for (size_t index=0;index<2*(input_length+output_length);++index) {
    const exact_dyadic *value=index<2*input_length ? part((exact_gaussian *)&input[index/2],index%2)
        : part(&out[(index-2*input_length)/2],index%2);
    if (!exact_valid(value) || exact_overlap(trace,sizeof(*trace),value->limbs,value->capacity*sizeof(uint32_t))) return EXACT_INVALID;
    if (value->capacity>capacity) capacity=value->capacity;
    for (size_t previous=0;previous<index;++previous) {
      const exact_dyadic *other=previous<2*input_length ? part((exact_gaussian *)&input[previous/2],previous%2)
          : part(&out[(previous-2*input_length)/2],previous%2);
      if (exact_alias_invalid(value,other)) return EXACT_INVALID;
    }
  }
  if (capacity>64) return EXACT_CAPACITY;
  if (inverse) for (unsigned row=0;row<4;++row) for (unsigned column=0;column<8;++column)
    if ((row>=3 || column>=5) && (input[row*8+column].real.length || input[row*8+column].imaginary.length)) return EXACT_INVALID;
  exact_gaussian work[2][32]={0}; exact_status status=EXACT_OK; composition_trace receipt={0}; unsigned bank=0;
  for (unsigned which=0;which<2;++which) for (unsigned index=0;index<32;++index) for (unsigned component=0;component<2;++component)
    TRY(exact_init(part(&work[which][index],component),capacity));
  if (inverse) {
    for (unsigned index=0;index<32;++index) { TRY(copy(&work[0][index],&input[index])); ++receipt.crt_moves; }
  } else {
    /* Mixed-radix a0 is the fast original digit. The scalar tensor API keeps
     * axis 1 as the contiguous polynomial suffix, so this physical placement
     * is explicit rather than inferred from the original stream order. */
    for (unsigned index=0;index<15;++index) { TRY(copy(&work[0][(index%3)*8+index/3],&input[index])); ++receipt.crt_moves; }
    if (observer) TRY(observer(context,"padding",work[0],32));
  }
  for (unsigned step=0;step<2;++step) {
    unsigned axis=inverse ? step : 1-step,next=1-bank;
    for (unsigned row=0;row<4;++row) for (unsigned column=0;column<8;++column) {
      unsigned target_row=row,target_column=column;
      if (row<3 && column<5 && axis==1) {
        unsigned shift=(parameters->inverse_prefix[1]*row)%5;
#ifdef MUTANT_CRT_DIRECTION
        shift=(5-shift)%5;
#endif
        target_column=(column+(inverse ? 5-shift : shift))%5;
      }
      /* Axis 0 has no lower coordinates, hence its controlled shift is zero.
       * Both valid and padded intervals still execute the prescribed copy. */
      TRY(copy(&work[next][target_row*8+target_column],&work[bank][row*8+column])); ++receipt.crt_moves;
    }
    bank=next; ++receipt.stages;
    if (observer) TRY(observer(context,axis ? "crt-axis-1" : "crt-axis-0",work[bank],32));
  }
  for (unsigned index=0;index<output_length;++index) {
    unsigned from=inverse ? (index%3)*8+index/3 : index;
    if (work[bank][from].real.length>out[index].real.capacity || work[bank][from].imaginary.length>out[index].imaginary.capacity) { status=EXACT_CAPACITY; goto done; }
  }
  for (unsigned index=0;index<output_length;++index) {
    unsigned from=inverse ? (index%3)*8+index/3 : index;
    TRY(copy(&out[index],&work[bank][from])); ++receipt.crt_moves;
  }
done:
  for (unsigned which=0;which<2;++which) for (unsigned index=0;index<32;++index) {
    exact_clear(&work[which][index].real); exact_clear(&work[which][index].imaginary);
  }
  *trace=receipt; return status;
}
