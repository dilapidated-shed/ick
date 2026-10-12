#include "numerical.h"
#include "exact_internal.h"
#include <stdlib.h>
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
exact_status short_mul_schoolbook(exact_dyadic *out,const exact_dyadic *left,const exact_dyadic *right) {
  if (!exact_valid(out) || !exact_valid(left) || !exact_valid(right) || left->binary_scale || right->binary_scale
      || left->sign<0 || right->sign<0 || exact_alias_invalid(out,left) || exact_alias_invalid(out,right)
      || exact_alias_invalid(left,right)) return EXACT_INVALID;
  exact_dyadic result={0}; exact_status status=exact_init(&result,out->capacity);
  if (status!=EXACT_OK) return status;
  if (left->length && right->length) {
    if (right->length>out->capacity || left->length>out->capacity-right->length) { status=EXACT_CAPACITY; goto done; }
    result.length=left->length+right->length; result.sign=1;
    for (size_t first=0;first<left->length;++first) {
      uint64_t carry=0;
      for (size_t second=0;second<right->length;++second) {
        size_t index=first+second;
        uint64_t value=(uint64_t)left->limbs[first]*right->limbs[second]+result.limbs[index]+carry;
        result.limbs[index]=(uint32_t)value; carry=value>>32;
      }
      result.limbs[first+right->length]=(uint32_t)carry;
    }
    exact_normalize(&result);
  }
  status=exact_copy(out,&result);
done:
  exact_clear(&result); return status;
}
static const exact_dyadic *part(const exact_gaussian *values,unsigned index,unsigned imaginary) {
  return imaginary ? &values[index].imaginary : &values[index].real;
}
static exact_status pack_stream(exact_dyadic *out,const exact_gaussian *values,unsigned length,unsigned precision,unsigned imaginary) {
  size_t bits=(size_t)4*precision*length,words=(bits+31)/32;
  if (words>out->capacity) return EXACT_CAPACITY;
  exact_dyadic base={0},coefficient={0},block={0},carry_value={0}; exact_status status=EXACT_OK;
  TRY(exact_init(&base,out->capacity)); TRY(exact_init(&coefficient,out->capacity));
  TRY(exact_init(&block,out->capacity)); TRY(exact_init(&carry_value,out->capacity));
  TRY(exact_set(&base,1,0)); TRY(exact_shift(&base,&base,4*precision));
  memset(out->limbs,0,words*sizeof(uint32_t)); int carry=0;
  for (unsigned index=0;index<length;++index) {
    TRY(exact_shift(&coefficient,part(values,index,imaginary),precision));
    TRY(exact_set(&carry_value,carry,0)); TRY(exact_add(&block,&coefficient,&carry_value));
    if (block.sign<0) { TRY(exact_add(&block,&block,&base)); carry=-1; } else carry=0;
    if (block.sign<0 || exact_bits(&block)>4*precision) { status=EXACT_INVALID; goto done; }
    for (unsigned bit=0;bit<4*precision;++bit) if (bit/32<block.length && ((block.limbs[bit/32]>>(bit%32))&1)) {
      size_t address=(size_t)index*4*precision+bit;
      out->limbs[address/32]|=UINT32_C(1)<<(address%32);
    }
  }
  out->length=words; out->sign=carry ? -1 : 1; out->binary_scale=0;
  if (carry) {
    uint64_t increment=1;
    for (size_t index=0;index<words;++index) {
      uint64_t value=(uint64_t)(uint32_t)~out->limbs[index]+increment;
      out->limbs[index]=(uint32_t)value; increment=value>>32;
    }
    if (bits%32) out->limbs[words-1]&=(UINT32_C(1)<<(bits%32))-1;
  }
  exact_normalize(out);
  if (exact_bits(out)>=bits) status=EXACT_INVALID;
done:
  exact_clear(&base); exact_clear(&coefficient); exact_clear(&block); exact_clear(&carry_value); return status;
}
static exact_status unpack_product(const exact_dyadic *product,unsigned length,unsigned precision,exact_dyadic *coefficients) {
  size_t bits=(size_t)8*precision*length,width=bits/8;
  uint8_t *bytes=calloc(width,1); if (!bytes) return EXACT_ALLOCATION;
  exact_dyadic base={0},half={0},carry_value={0}; exact_status status=EXACT_OK;
  TRY(exact_init(&base,product->capacity)); TRY(exact_init(&half,product->capacity)); TRY(exact_init(&carry_value,product->capacity));
  TRY(exact_set(&base,1,0)); TRY(exact_shift(&base,&base,4*precision)); TRY(exact_half(&half,&base));
  TRY(exact_serialize(product,0,bytes,width)); unsigned carry=0;
  for (unsigned index=0;index<2*length;++index) {
    exact_dyadic *coefficient=&coefficients[index];
    size_t words=(4*(size_t)precision+31)/32;
    if (words>coefficient->capacity) { status=EXACT_CAPACITY; goto done; }
    memset(coefficient->limbs,0,words*sizeof(uint32_t));
    for (unsigned bit=0;bit<4*precision;++bit) {
      size_t address=(size_t)index*4*precision+bit;
      if ((bytes[width-1-address/8]>>(address%8))&1) coefficient->limbs[bit/32]|=UINT32_C(1)<<(bit%32);
    }
    coefficient->length=words; coefficient->sign=1; coefficient->binary_scale=0; exact_normalize(coefficient);
    TRY(exact_set(&carry_value,carry,0)); TRY(exact_add(coefficient,coefficient,&carry_value));
    int comparison; TRY(exact_compare(&comparison,coefficient,&half));
    if (comparison>=0) { TRY(exact_subtract(coefficient,coefficient,&base)); carry=1; } else carry=0;
    if (exact_bits(coefficient)>3*(size_t)precision) { status=EXACT_INVALID; goto done; }
  }
  if (coefficients[2*length-1].length || carry!=(unsigned)(product->sign<0)) status=EXACT_INVALID;
done:
  exact_clear(&base); exact_clear(&half); exact_clear(&carry_value); free(bytes); return status;
}
static exact_status check_disk(const exact_gaussian *value,unsigned precision,size_t capacity,uint64_t *products) {
  if (!exact_valid(&value->real) || !exact_valid(&value->imaginary)
      || value->real.binary_scale>precision || value->imaginary.binary_scale>precision) return EXACT_INVALID;
  exact_dyadic real={0},imaginary={0},square_real={0},square_imaginary={0},bound={0}; exact_status status=EXACT_OK;
  TRY(exact_init(&real,capacity)); TRY(exact_init(&imaginary,capacity)); TRY(exact_init(&square_real,capacity));
  TRY(exact_init(&square_imaginary,capacity)); TRY(exact_init(&bound,capacity));
  TRY(exact_shift(&real,&value->real,precision)); TRY(exact_shift(&imaginary,&value->imaginary,precision));
  if (real.sign<0) real.sign=1;
  if (imaginary.sign<0) imaginary.sign=1;
  TRY(short_mul_schoolbook(&square_real,&real,&real)); ++*products;
  TRY(short_mul_schoolbook(&square_imaginary,&imaginary,&imaginary)); ++*products;
  TRY(exact_add(&square_real,&square_real,&square_imaginary)); TRY(exact_set(&bound,1,0)); TRY(exact_shift(&bound,&bound,2*precision));
  int comparison; TRY(exact_compare(&comparison,&square_real,&bound)); if (comparison>0) status=EXACT_INVALID;
done:
  exact_clear(&real); exact_clear(&imaginary); exact_clear(&square_real); exact_clear(&square_imaginary); exact_clear(&bound); return status;
}
exact_status packed_product_observed(const exact_gaussian *first,const exact_gaussian *second,unsigned length,unsigned precision,
                                       exact_gaussian *out,const short_mul_provider *provider,short_mul_trace *trace,
                                       numerical_product_observer observer,void *observer_context) {
  if (!first || !second || !out || !provider || !provider->identity || !provider->multiply || !trace
      || precision<2 || precision>256 || length<2 || length>8 || (length&(length-1)) || length>=((precision<4) ? 1u<<precision : 16u)
      || exact_overlap(first,length*sizeof(*first),out,length*sizeof(*out))
      || exact_overlap(second,length*sizeof(*second),out,length*sizeof(*out))
      || exact_overlap(trace,sizeof(*trace),first,length*sizeof(*first))
      || exact_overlap(trace,sizeof(*trace),second,length*sizeof(*second))
      || exact_overlap(trace,sizeof(*trace),out,length*sizeof(*out))
      || exact_overlap(trace,sizeof(*trace),provider,sizeof(*provider))) return EXACT_INVALID;
  for (unsigned index=0;index<6*length;++index) {
    unsigned bank=index/(2*length),local=index%(2*length);
    const exact_dyadic *value=part(bank==0 ? first : bank==1 ? second : out,local/2,local%2);
    if (!exact_valid(value) || exact_overlap(trace,sizeof(*trace),value->limbs,value->capacity*sizeof(uint32_t))) return EXACT_INVALID;
    for (unsigned previous=0;previous<index;++previous) {
      unsigned previous_bank=previous/(2*length),previous_local=previous%(2*length);
      const exact_dyadic *other=part(previous_bank==0 ? first : previous_bank==1 ? second : out,previous_local/2,previous_local%2);
      if (exact_alias_invalid(value,other)) return EXACT_INVALID;
    }
  }
  unsigned logarithm=0; for (unsigned value=length;value>1;value>>=1) ++logarithm;
  size_t capacity=(8*(size_t)precision*length+31)/32+2;
  short_mul_trace observed={0}; observed.identity=provider->identity;
  exact_dyadic packed[4]={{0}},products[4]={{0}},*coefficients=NULL;
  exact_gaussian *result=NULL; exact_status status=EXACT_OK;
  for (unsigned index=0;index<length;++index) {
    TRY(check_disk(&first[index],precision,capacity,&observed.validation_products));
    TRY(check_disk(&second[index],precision,capacity,&observed.validation_products));
    for (unsigned component=0;component<2;++component) if (!exact_valid(part(out,index,component))) { status=EXACT_INVALID; goto done; }
  }
  for (unsigned index=0;index<4;++index) {
    TRY(exact_init(&packed[index],capacity)); TRY(exact_init(&products[index],capacity));
    TRY(pack_stream(&packed[index],index<2 ? first : second,length,precision,index%2));
  }
  const unsigned left[]={0,1,0,1},right[]={2,3,3,2};
  for (unsigned index=0;index<4;++index) {
    int sign=packed[left[index]].sign*packed[right[index]].sign;
    int left_sign=packed[left[index]].sign,right_sign=packed[right[index]].sign;
    if (packed[left[index]].sign<0) packed[left[index]].sign=1;
    if (packed[right[index]].sign<0) packed[right[index]].sign=1;
    observed.left_bits[index]=exact_bits(&packed[left[index]]); observed.right_bits[index]=exact_bits(&packed[right[index]]);
    ++observed.calls;
    status=provider->multiply(&products[index],&packed[left[index]],&packed[right[index]]);
#ifdef MUTANT_ONE_PRODUCT
    if (index==1 && status==EXACT_OK) status=exact_set(&products[index],0,0);
#endif
    packed[left[index]].sign=left_sign; packed[right[index]].sign=right_sign;
    if (status!=EXACT_OK) goto done;
    if (!exact_valid(&products[index]) || products[index].binary_scale || products[index].sign<0) { status=EXACT_INVALID; goto done; }
    if (products[index].length && !sign) { status=EXACT_INVALID; goto done; }
    if (products[index].length) products[index].sign=sign;
    observed.result_bits[index]=exact_bits(&products[index]);
  }
  coefficients=calloc(8*length,sizeof(*coefficients)); result=calloc(length,sizeof(*result));
  if (!coefficients || !result) { status=EXACT_ALLOCATION; goto done; }
  for (unsigned index=0;index<8*length;++index) TRY(exact_init(&coefficients[index],capacity));
  for (unsigned index=0;index<length;++index) { TRY(exact_init(&result[index].real,capacity)); TRY(exact_init(&result[index].imaginary,capacity)); }
  for (unsigned product=0;product<4;++product) TRY(unpack_product(&products[product],length,precision,&coefficients[product*2*length]));
  for (unsigned index=0;index<length;++index) for (unsigned component=0;component<2;++component) {
    exact_dyadic *destination=component ? &result[index].imaginary : &result[index].real;
    unsigned first_product=component ? 2 : 0,second_product=component ? 3 : 1;
    exact_dyadic *a=&coefficients[first_product*2*length+index],*b=&coefficients[second_product*2*length+index];
    exact_dyadic *high_a=&coefficients[first_product*2*length+index+length],*high_b=&coefficients[second_product*2*length+index+length];
    TRY(exact_subtract(a,a,high_a)); TRY(exact_subtract(b,b,high_b));
    TRY(component ? exact_add(destination,a,b) : exact_subtract(destination,a,b));
  }
  if (observer) TRY(observer(observer_context,result,length));
  for (unsigned index=0;index<length;++index) for (unsigned component=0;component<2;++component) {
    exact_dyadic *destination=component ? &result[index].imaginary : &result[index].real;
    if (destination->length) destination->binary_scale=2*precision+logarithm;
    exact_normalize(destination); TRY(exact_truncate(destination,destination,precision));
    if (destination->length>part(out,index,component)->capacity) { status=EXACT_CAPACITY; goto done; }
  }
  for (unsigned index=0;index<length;++index) { TRY(exact_copy(&out[index].real,&result[index].real)); TRY(exact_copy(&out[index].imaginary,&result[index].imaginary)); }
done:
  *trace=observed;
  for (unsigned index=0;index<4;++index) { exact_clear(&packed[index]); exact_clear(&products[index]); }
  if (coefficients) { for (unsigned index=0;index<8*length;++index) exact_clear(&coefficients[index]); free(coefficients); }
  if (result) { for (unsigned index=0;index<length;++index) { exact_clear(&result[index].real); exact_clear(&result[index].imaginary); } free(result); }
  return status;
}
exact_status packed_product(const exact_gaussian *first,const exact_gaussian *second,unsigned length,unsigned precision,
                              exact_gaussian *out,const short_mul_provider *provider,short_mul_trace *trace) {
  return packed_product_observed(first,second,length,precision,out,provider,trace,NULL,NULL);
}
