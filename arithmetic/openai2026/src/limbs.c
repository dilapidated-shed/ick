#include "exact_internal.h"
#include <stdlib.h>
#include <string.h>

int exact_overlap(const void *a, size_t an, const void *b, size_t bn) {
  uintptr_t x = (uintptr_t)a, y = (uintptr_t)b;
  if (!an || !bn) return 0;
  return x <= y ? y-x < an : x-y < bn;
}
int exact_valid(const exact_dyadic *v) {
  if (!v || v->capacity > SIZE_MAX/32 || v->length > v->capacity
      || (v->capacity && !v->limbs)) return 0;
  if (!v->length) return v->sign == 0 && v->binary_scale == 0;
  return (v->sign == 1 || v->sign == -1) && v->limbs[v->length-1]
    && (!v->binary_scale || (v->limbs[0] & 1));
}
int exact_alias_invalid(const exact_dyadic *a, const exact_dyadic *b) {
  return a != b && exact_overlap(a->limbs,a->capacity*sizeof(uint32_t),
                                  b->limbs,b->capacity*sizeof(uint32_t));
}
void exact_normalize(exact_dyadic *v) {
  while (v->length && !v->limbs[v->length-1]) --v->length;
  if (!v->length) { v->sign = 0; v->binary_scale = 0; return; }
  while (v->binary_scale && !(v->limbs[0]&1)) {
    uint32_t carry = 0;
    for (size_t j=v->length; j; --j) {
      uint32_t limb = v->limbs[j-1];
      v->limbs[j-1] = (limb>>1) | carry;
      carry = limb<<31;
    }
    --v->binary_scale;
    while (v->length && !v->limbs[v->length-1]) --v->length;
  }
}
exact_status exact_init(exact_dyadic *v, size_t capacity) {
  if (!v) return EXACT_INVALID;
  *v = (exact_dyadic){0};
  if (capacity > SIZE_MAX/32) return EXACT_CAPACITY;
  if (capacity && !(v->limbs=calloc(capacity,sizeof(uint32_t))))
    return EXACT_ALLOCATION;
  v->capacity = capacity;
  return EXACT_OK;
}
void exact_clear(exact_dyadic *v) {
  if (v) { free(v->limbs); *v=(exact_dyadic){0}; }
}
exact_status exact_copy(exact_dyadic *out, const exact_dyadic *in) {
  if (!exact_valid(out) || !exact_valid(in) || exact_alias_invalid(out,in))
    return EXACT_INVALID;
  if (in->length > out->capacity) return EXACT_CAPACITY;
  if (out == in) return EXACT_OK;
  if (in->length) memcpy(out->limbs,in->limbs,in->length*sizeof(uint32_t));
  out->length=in->length; out->sign=in->sign; out->binary_scale=in->binary_scale;
  return EXACT_OK;
}
exact_status exact_set(exact_dyadic *out, int64_t numerator, size_t scale) {
  if (!exact_valid(out)) return EXACT_INVALID;
  uint64_t magnitude = numerator < 0 ? (uint64_t)(-(numerator+1))+1 : (uint64_t)numerator;
  size_t length = magnitude > UINT32_MAX ? 2 : magnitude ? 1 : 0;
  if (length > out->capacity) return EXACT_CAPACITY;
  if (length) out->limbs[0]=(uint32_t)magnitude;
  if (length>1) out->limbs[1]=(uint32_t)(magnitude>>32);
  out->length=length; out->sign=numerator<0 ? -1 : numerator>0 ? 1 : 0;
  out->binary_scale=scale; exact_normalize(out); return EXACT_OK;
}
size_t exact_bits(const exact_dyadic *v) {
  if (!v->length) return 0;
  uint32_t high=v->limbs[v->length-1]; size_t bits=0;
  while (high) { ++bits; high>>=1; }
  return (v->length-1)*32+bits;
}
exact_status exact_magnitude_shift(exact_dyadic *out, const exact_dyadic *in, size_t bits) {
  if (!in->length) { out->length=0; out->sign=0; out->binary_scale=0; return EXACT_OK; }
  size_t words=bits/32, residue=bits%32;
  int extra=residue && (in->limbs[in->length-1]>>(32-residue));
  if (words > out->capacity || in->length > out->capacity-words
      || (extra && in->length == out->capacity-words)) return EXACT_CAPACITY;
  size_t length=in->length+words+extra;
  memset(out->limbs,0,length*sizeof(uint32_t));
  for (size_t j=0;j<in->length;++j) {
    out->limbs[j+words] |= in->limbs[j]<<residue;
    if (residue && j+words+1<length) out->limbs[j+words+1] |= in->limbs[j]>>(32-residue);
  }
  out->length=length; out->sign=in->sign; out->binary_scale=0;
  return EXACT_OK;
}
static int magnitude_compare(const exact_dyadic *a, const exact_dyadic *b) {
  size_t ab=exact_bits(a), bb=exact_bits(b);
  int ap=ab>=a->binary_scale, bp=bb>=b->binary_scale;
  size_t ae=ap ? ab-a->binary_scale : a->binary_scale-ab;
  size_t be=bp ? bb-b->binary_scale : b->binary_scale-bb;
  if (ap!=bp) return ap ? 1 : -1;
  if (ae!=be) return ap ? (ae>be ? 1 : -1) : (ae<be ? 1 : -1);
  size_t count=ab>bb ? ab : bb;
  for (size_t k=0;k<count;++k) {
    int x=k<ab ? (a->limbs[(ab-1-k)/32]>>((ab-1-k)%32))&1 : 0;
    int y=k<bb ? (b->limbs[(bb-1-k)/32]>>((bb-1-k)%32))&1 : 0;
    if (x!=y) return x>y ? 1 : -1;
  }
  return 0;
}
exact_status exact_compare(int *order, const exact_dyadic *a, const exact_dyadic *b) {
  if (!order || !exact_valid(a) || !exact_valid(b) || exact_alias_invalid(a,b)
      || exact_overlap(order,sizeof(*order),a->limbs,a->capacity*sizeof(uint32_t))
      || exact_overlap(order,sizeof(*order),b->limbs,b->capacity*sizeof(uint32_t))) return EXACT_INVALID;
  *order=a->sign!=b->sign ? (a->sign>b->sign ? 1 : -1)
    : !a->sign ? 0 : a->sign*magnitude_compare(a,b);
  return EXACT_OK;
}
