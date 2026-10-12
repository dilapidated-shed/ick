#include "composition.h"
#include <stdio.h>
typedef struct { unsigned test,inverse; } observation;
static exact_status emit(void *opaque,const char *stage,const exact_gaussian *values,size_t length) {
  observation *context=opaque;
  for (size_t index=0;index<length;++index) {
    unsigned char real[2],imaginary[2];
    if (exact_serialize(&values[index].real,9,real,2) || exact_serialize(&values[index].imaginary,9,imaginary,2)) return EXACT_INVALID;
    printf("crt\t%u\t%u\t%s\t%zu\t%02x%02x\t%02x%02x\n",context->test,context->inverse,stage,index,real[0],real[1],imaginary[0],imaginary[1]);
  }
  return ferror(stdout) ? EXACT_INVALID : EXACT_OK;
}
int main(void) {
  composition_parameters parameters; recovery_certificate certificate; exact_gaussian input[15]={0},box[32]={0},restored[15]={0};
  if (composition_admit(REDUCED_ALGEBRA,&parameters,&certificate)) return 62;
  for (unsigned index=0;index<32;++index) {
    if (exact_init(&box[index].real,4) || exact_init(&box[index].imaginary,4)) return 62;
    if (index<15 && (exact_init(&input[index].real,4) || exact_init(&input[index].imaginary,4)
       || exact_init(&restored[index].real,4) || exact_init(&restored[index].imaginary,4))) return 62;
  }
  for (unsigned test=0;test<32;++test) {
    for (unsigned index=0;index<15;++index) {
      int64_t real=test<15 ? index==test : test<30 ? 0 : (int64_t)index-7;
      int64_t imaginary=test<15 ? 0 : test<30 ? index==test-15 : 2*(int64_t)index-13;
      unsigned scale=test<30 ? 0 : 9;
      if (test==31) { real=9-(int64_t)index; imaginary=(int64_t)((index*7+2)%11)-5; scale=2; }
      if (exact_set(&input[index].real,real,scale) || exact_set(&input[index].imaginary,imaginary,scale)) return 62;
    }
    observation context={test,0}; composition_trace trace={0};
    if (composition_crt(&parameters,input,15,box,32,0,&trace,emit,&context) || emit(&context,"forward",box,32)) return 63;
    context.inverse=1;
    if (composition_crt(&parameters,box,32,restored,15,1,&trace,emit,&context) || emit(&context,"inverse",restored,15)) return 63;
  }
  for (unsigned index=0;index<32;++index) {
    exact_clear(&box[index].real); exact_clear(&box[index].imaginary);
    if (index<15) { exact_clear(&input[index].real); exact_clear(&input[index].imaginary); exact_clear(&restored[index].real); exact_clear(&restored[index].imaginary); }
  }
  return ferror(stdout) ? 64 : 0;
}
