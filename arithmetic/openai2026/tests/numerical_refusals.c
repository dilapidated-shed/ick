#include "numerical.h"
#include <stdio.h>
#include <stdlib.h>

static int refusal(const char *name,exact_status status,exact_status expected) {
  printf("refusal\t%s\t%u\n",name,status); return status==expected;
}
static int fresh(exact_gaussian *values,unsigned count,size_t capacity) {
  for (unsigned index=0;index<count;++index)
    if (exact_init(&values[index].real,capacity) || exact_init(&values[index].imaginary,capacity)) return 0;
  return 1;
}
static int sentinel(exact_gaussian *values,unsigned count) {
  for (unsigned index=0;index<count;++index)
    if (exact_set(&values[index].real,7,3) || exact_set(&values[index].imaginary,-7,3)) return 0;
  return 1;
}
static int preserved(const exact_gaussian *values,unsigned count) {
  for (unsigned index=0;index<count;++index) {
    unsigned char real[2],imaginary[2];
    if (exact_serialize(&values[index].real,9,real,2) || exact_serialize(&values[index].imaginary,9,imaginary,2)
        || real[0]!=1 || real[1]!=0xc0 || imaginary[0]!=0xfe || imaginary[1]!=0x40) return 0;
  }
  return 1;
}
int main(void) {
  int success=1; synthetic_plan *shape=NULL,*low=NULL; phase_layer_plan *layer=NULL;
  const unsigned axes[]={2,2},wrong[]={2,3},giant[]={8,8,8,8};
  success&=refusal("precision-low",synthetic_prepare(1,2,axes,2,65536,&shape),EXACT_INVALID);
  success&=refusal("precision-high",synthetic_prepare(257,2,axes,2,65536,&shape),EXACT_INVALID);
  success&=refusal("ring",synthetic_prepare(9,3,axes,2,65536,&shape),EXACT_INVALID);
  success&=refusal("axis-length",synthetic_prepare(9,2,wrong,2,65536,&shape),EXACT_INVALID);
  success&=refusal("no-axes",synthetic_prepare(9,2,axes,0,65536,&shape),EXACT_INVALID);
  success&=refusal("record-limit",synthetic_prepare(9,8,giant,4,65536,&shape),EXACT_CAPACITY);
  success&=refusal("record-budget",synthetic_prepare(9,2,axes,2,1,&shape),EXACT_CAPACITY);
  success&=refusal("published-fixed",numerical_published_admission(),EXACT_INVALID);
  success&=refusal("phase-precision",phase_layer_prepare(1,2,65536,&layer),EXACT_INVALID);
  success&=refusal("phase-axes",phase_layer_prepare(9,5,65536,&layer),EXACT_INVALID);
  success&=refusal("phase-budget",phase_layer_prepare(9,2,1,&layer),EXACT_CAPACITY);
  if (!success || shape || layer || synthetic_prepare(9,2,axes,2,65536,&shape)
      || synthetic_prepare(2,2,axes,2,65536,&low) || phase_layer_prepare(9,2,65536,&layer)) return 47;
  success&=refusal("fresh-plan",synthetic_prepare(9,2,axes,2,65536,&shape),EXACT_INVALID);
  exact_gaussian input[8]={0},output[8]={0},empty[8]={0};
  if (!fresh(input,8,8) || !fresh(output,8,8) || !fresh(empty,8,0) || !sentinel(output,8)) return 48;
  numerical_trace trace={0}; phase_layer_trace phase_trace={0}; short_mul_trace short_trace={0};
  const short_mul_provider provider={"reduced-schoolbook",short_mul_schoolbook},bad={NULL,NULL};
  if (exact_set(&input[0].real,2,0)) return 48;
  success&=refusal("phase-disk",phase_layer_apply(layer,input,1,output,&phase_trace),EXACT_INVALID) && preserved(output,8);
  success&=refusal("transform-disk",synthetic_transform(shape,input,output,0,&trace,NULL,NULL),EXACT_INVALID) && preserved(output,8);
  if (exact_set(&input[0].real,1,10)) return 48;
  success&=refusal("phase-grid",phase_layer_apply(layer,input,1,output,&phase_trace),EXACT_INVALID) && preserved(output,8);
  success&=refusal("transform-grid",synthetic_transform(shape,input,output,0,&trace,NULL,NULL),EXACT_INVALID) && preserved(output,8);
  if (exact_set(&input[0].real,0,0) || exact_set(&input[4].real,1,2)) return 48;
  success&=refusal("nonprimary-X",phase_layer_apply(layer,input,2,output,&phase_trace),EXACT_INVALID) && preserved(output,8);
  if (exact_set(&input[4].real,0,0)) return 48;
  success&=refusal("phase-alias",phase_layer_apply(layer,input,1,input,&phase_trace),EXACT_INVALID);
  success&=refusal("transform-alias",synthetic_transform(shape,input,input,0,&trace,NULL,NULL),EXACT_INVALID);
  success&=refusal("trace-alias",synthetic_transform(shape,input,output,0,(numerical_trace *)input[0].real.limbs,NULL,NULL),EXACT_INVALID) && preserved(output,8);
  success&=refusal("convolution-margin",numerical_convolution(low,input,input,output,&provider,&trace),EXACT_INVALID) && preserved(output,8);
  success&=refusal("convolution-provider",numerical_convolution(shape,input,input,output,&bad,&trace),EXACT_INVALID) && preserved(output,8);
  if (exact_set(&input[0].real,1,0)) return 48;
  success&=refusal("convolution-radius",numerical_convolution(shape,input,input,output,&provider,&trace),EXACT_INVALID) && preserved(output,8);
  success&=refusal("phase-capacity",phase_layer_apply(layer,input,1,empty,&phase_trace),EXACT_CAPACITY);
  success&=refusal("transform-capacity",synthetic_transform(shape,input,empty,0,&trace,NULL,NULL),EXACT_CAPACITY);
  if (exact_set(&input[0].real,1,1)) return 48;
  success&=refusal("packed-precision",packed_product(input,input,2,1,output,&provider,&short_trace),EXACT_INVALID) && preserved(output,8);
  success&=refusal("packed-ring",packed_product(input,input,4,2,output,&provider,&short_trace),EXACT_INVALID) && preserved(output,8);
  success&=refusal("packed-alias",packed_product(input,input,2,9,input,&provider,&short_trace),EXACT_INVALID);
  success&=refusal("packed-capacity",packed_product(input,input,2,9,empty,&provider,&short_trace),EXACT_CAPACITY);
  for (unsigned index=0;index<8;++index) {
    if (empty[index].real.length || empty[index].imaginary.length) success=0;
    exact_clear(&input[index].real); exact_clear(&input[index].imaginary);
    exact_clear(&output[index].real); exact_clear(&output[index].imaginary);
    exact_clear(&empty[index].real); exact_clear(&empty[index].imaginary);
  }
  phase_layer_clear(layer); synthetic_clear(shape); synthetic_clear(low);
  return success && !ferror(stdout) ? 0 : 49;
}
