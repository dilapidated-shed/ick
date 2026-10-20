#include "exact_internal.h"
#include <string.h>

static exact_status inputs(exact_dyadic *out, const exact_dyadic *a, const exact_dyadic *b) {
  return exact_valid(out) && exact_valid(a) && exact_valid(b)
    && !exact_alias_invalid(out,a) && !exact_alias_invalid(out,b)
    && !exact_alias_invalid(a,b) ? EXACT_OK : EXACT_INVALID;
}
static int raw_compare(const exact_dyadic *a, const exact_dyadic *b) {
  if (a->length!=b->length) return a->length>b->length ? 1 : -1;
  for (size_t j=a->length;j;--j)
    if (a->limbs[j-1]!=b->limbs[j-1]) return a->limbs[j-1]>b->limbs[j-1] ? 1 : -1;
  return 0;
}
static exact_status combine(exact_dyadic *out, const exact_dyadic *a,
                            const exact_dyadic *b, int direction) {
  exact_status status=inputs(out,a,b);
  if (status!=EXACT_OK) return status;
  size_t scale=a->binary_scale>b->binary_scale ? a->binary_scale : b->binary_scale;
  exact_dyadic left={0},right={0},result={0};
  if ((status=exact_init(&left,out->capacity))!=EXACT_OK
      || (status=exact_init(&right,out->capacity))!=EXACT_OK
      || (status=exact_init(&result,out->capacity))!=EXACT_OK) goto done;
  if ((status=exact_magnitude_shift(&left,a,scale-a->binary_scale))!=EXACT_OK
      || (status=exact_magnitude_shift(&right,b,scale-b->binary_scale))!=EXACT_OK) goto done;
  right.sign*=direction;
  size_t length=left.length>right.length ? left.length : right.length;
  result.length=length; result.binary_scale=scale;
  if (left.sign==right.sign) {
    uint64_t carry=0;
    for (size_t j=0;j<length;++j) {
      uint64_t sum=carry+(j<left.length ? left.limbs[j] : 0)
                        +(uint64_t)(j<right.length ? right.limbs[j] : 0);
      result.limbs[j]=(uint32_t)sum; carry=sum>>32;
#ifdef MUTANT_DROPPED_CARRY
      carry=0;
#endif
    }
    if (carry) {
      if (length==result.capacity) { status=EXACT_CAPACITY; goto done; }
      result.limbs[result.length++]=(uint32_t)carry;
    }
    result.sign=left.sign;
  } else {
    int order=raw_compare(&left,&right);
    const exact_dyadic *larger=order>=0 ? &left : &right;
    const exact_dyadic *smaller=order>=0 ? &right : &left;
    uint64_t borrow=0;
    for (size_t j=0;j<length;++j) {
      uint64_t top=j<larger->length ? larger->limbs[j] : 0;
      uint64_t bottom=borrow+(uint64_t)(j<smaller->length ? smaller->limbs[j] : 0);
      result.limbs[j]=(uint32_t)(top-bottom); borrow=top<bottom;
    }
    result.sign=larger->sign;
  }
  exact_normalize(&result); status=exact_copy(out,&result);
done:
  exact_clear(&left); exact_clear(&right); exact_clear(&result); return status;
}
exact_status exact_add(exact_dyadic *out, const exact_dyadic *a, const exact_dyadic *b) {
  return combine(out,a,b,1);
}
exact_status exact_subtract(exact_dyadic *out, const exact_dyadic *a, const exact_dyadic *b) {
  return combine(out,a,b,-1);
}
exact_status exact_shift(exact_dyadic *out, const exact_dyadic *in, size_t bits) {
  if (!exact_valid(out) || !exact_valid(in) || exact_alias_invalid(out,in)) return EXACT_INVALID;
  exact_dyadic result={0}; exact_status status=exact_init(&result,out->capacity);
  if (status!=EXACT_OK) return status;
  size_t cancelled=bits<in->binary_scale ? bits : in->binary_scale;
  status=exact_magnitude_shift(&result,in,bits-cancelled);
  if (status==EXACT_OK) {
    result.binary_scale=in->binary_scale-cancelled;
    exact_normalize(&result); status=exact_copy(out,&result);
  }
  exact_clear(&result); return status;
}
exact_status exact_half(exact_dyadic *out, const exact_dyadic *in) {
  if (!exact_valid(out) || !exact_valid(in) || exact_alias_invalid(out,in)) return EXACT_INVALID;
  if (in->length && in->binary_scale==SIZE_MAX) return EXACT_CAPACITY;
  exact_status status=exact_copy(out,in);
  if (status==EXACT_OK && out->length) { ++out->binary_scale; exact_normalize(out); }
  return status;
}
exact_status exact_truncate(exact_dyadic *out, const exact_dyadic *in, size_t scale) {
  if (!exact_valid(out) || !exact_valid(in) || exact_alias_invalid(out,in)) return EXACT_INVALID;
  if (scale>=in->binary_scale) return exact_copy(out,in);
  exact_dyadic result={0}; exact_status status=exact_init(&result,out->capacity);
  if (status!=EXACT_OK) return status;
  size_t bits=in->binary_scale-scale, words=bits/32, residue=bits%32;
  size_t length=words<in->length ? in->length-words : 0;
  if (length && residue && !(in->limbs[in->length-1]>>residue)) --length;
  if (length>result.capacity) { status=EXACT_CAPACITY; goto done; }
  for (size_t j=0;j<length;++j) {
    result.limbs[j]=in->limbs[j+words]>>residue;
    if (residue && j+words+1<in->length) result.limbs[j]|=in->limbs[j+words+1]<<(32-residue);
  }
  result.length=length; result.sign=in->sign; result.binary_scale=scale;
  exact_normalize(&result); status=exact_copy(out,&result);
done:
  exact_clear(&result); return status;
}
exact_status exact_serialize(const exact_dyadic *in, size_t scale, uint8_t *out, size_t width) {
  if (!exact_valid(in) || !out || !width || width>SIZE_MAX/8
      || scale<in->binary_scale
      || exact_overlap(out,width,in,sizeof(*in))
      || exact_overlap(out,width,in->limbs,in->capacity*sizeof(uint32_t))) return EXACT_INVALID;
  size_t shift=scale-in->binary_scale, bits=exact_bits(in), available=width*8;
  if (bits && (shift>available || bits>available-shift)) return EXACT_CAPACITY;
  if (bits && bits+shift==available) {
    if (in->sign>0) return EXACT_CAPACITY;
    int power_of_two=1;
    for (size_t j=0;j<in->length;++j) {
      uint32_t limb=in->limbs[j];
      if (j+1==in->length) power_of_two &= limb && !(limb&(limb-1));
      else power_of_two &= limb==0;
    }
    if (!power_of_two) return EXACT_CAPACITY;
  }
  memset(out,0,width);
  for (size_t j=0;j<bits;++j)
    if ((in->limbs[j/32]>>(j%32))&1) out[width-1-(j+shift)/8]|=(uint8_t)(1u<<((j+shift)%8));
  if (in->sign<0) {
    unsigned carry=1;
    for (size_t j=width;j;--j) {
      unsigned sum=(unsigned)(uint8_t)~out[j-1]+carry;
      out[j-1]=(uint8_t)sum; carry=sum>>8;
    }
  }
  return EXACT_OK;
}
