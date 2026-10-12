#include "numerical.h"
#include <stdio.h>
#include <stdlib.h>

static int emit(const exact_dyadic *value,unsigned bits,unsigned scale) {
  uint8_t bytes[80]; size_t width=(bits+9)/8;
  if (width>sizeof(bytes) || exact_serialize(value,scale,bytes,width)) return 0;
  for (size_t index=0;index<width;++index) printf("%02x",bytes[index]);
  return 1;
}
typedef struct { unsigned precision,test; } observer_context;
static exact_status observe(void *pointer,const exact_gaussian *values,unsigned length) {
  const observer_context *context=pointer; unsigned logarithm=0;
  for (unsigned value=length;value>1;value>>=1) ++logarithm;
  for (unsigned index=0;index<length;++index) {
    printf("numerator\t%u\t%u\t%u\t%u\t",context->precision,length,context->test,index);
    if (!emit(&values[index].real,2*context->precision+logarithm,0)) return EXACT_INVALID;
    putchar('\t'); if (!emit(&values[index].imaginary,2*context->precision+logarithm,0)) return EXACT_INVALID;
    putchar('\n');
  }
  return EXACT_OK;
}
static int initialize_input(exact_gaussian *values,unsigned length,unsigned precision,unsigned test,unsigned operand) {
  for (unsigned index=0;index<length;++index) {
    int64_t real=0,imaginary=0; unsigned scale=0;
    switch (test) {
      case 0: real=1; break;
      case 1: real=((index+operand)&1) ? -1 : 1; break;
      case 2: imaginary=operand && (index&1) ? -1 : 1; break;
      case 3: real=((index+operand)&1) ? -1 : 1; imaginary=(index&1) ? 1 : -1; scale=1; break;
      case 4: real=index==(operand ? 1 : length-1); break;
      case 5: real=(index&1) ? -1 : 1; imaginary=operand ? 1 : 0; scale=precision; break;
      case 6: real=operand ? 1 : 2; imaginary=operand ? 2 : -2; scale=2; break;
      case 7: real=(int64_t)((index*7+operand*3)%3)-1; imaginary=(int64_t)((index*11+operand*5)%5)-2; scale=2; break;
    }
    if (exact_set(&values[index].real,real,scale) || exact_set(&values[index].imaginary,imaginary,scale)) return 0;
  }
  return 1;
}
int main(void) {
  exact_gaussian first[8]={0},second[8]={0},output[8]={0};
  for (unsigned index=0;index<8;++index)
    if (exact_init(&first[index].real,32) || exact_init(&first[index].imaginary,32)
        || exact_init(&second[index].real,32) || exact_init(&second[index].imaginary,32)
        || exact_init(&output[index].real,32) || exact_init(&output[index].imaginary,32)) return 40;
  const unsigned precisions[]={2,3,5,9,33,101,256};
  short_mul_provider provider={"reduced-schoolbook",short_mul_schoolbook};
  for (unsigned profile=0;profile<7;++profile) for (unsigned length=2;length<=8;length*=2) {
    unsigned precision=precisions[profile]; if (precision<4 && length>=(1u<<precision)) continue;
    for (unsigned test=0;test<8;++test) {
      if (!initialize_input(first,length,precision,test,0) || !initialize_input(second,length,precision,test,1)) return 41;
      short_mul_trace trace={0}; observer_context context={precision,test};
      exact_status status=packed_product_observed(first,second,length,precision,output,&provider,&trace,observe,&context);
      if (status!=EXACT_OK) { fprintf(stderr,"packed refusal p=%u r=%u test=%u status=%u\n",precision,length,test,status); return 42; }
      if (trace.calls!=4 || trace.validation_products!=4*length) return 43;
      for (unsigned product=0;product<4;++product)
        printf("short\t%u\t%u\t%u\t%u\t%zu\t%zu\t%zu\t%s\n",precision,length,test,product,
               trace.left_bits[product],trace.right_bits[product],trace.result_bits[product],trace.identity);
      for (unsigned index=0;index<length;++index) {
        printf("packed\t%u\t%u\t%u\t%u\t",precision,length,test,index);
        if (!emit(&output[index].real,precision,precision)) return 44;
        putchar('\t'); if (!emit(&output[index].imaginary,precision,precision)) return 44;
        putchar('\n');
      }
    }
  }
  for (unsigned index=0;index<8;++index) {
    exact_clear(&first[index].real); exact_clear(&first[index].imaginary);
    exact_clear(&second[index].real); exact_clear(&second[index].imaginary);
    exact_clear(&output[index].real); exact_clear(&output[index].imaginary);
  }
  return ferror(stdout) ? 45 : 0;
}
