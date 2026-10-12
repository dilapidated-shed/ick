#include "certified_internal.h"
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static exact_status point_init(certified_scalar_context *context,exact_dyadic *value) {
  exact_status status=exact_init(value,CERTIFIED_LIMBS);
  if (status==EXACT_OK) {
    ++context->work.allocations; context->work.live_limb_bytes+=CERTIFIED_LIMBS*sizeof(uint32_t);
    if (context->work.live_limb_bytes>context->work.peak_limb_bytes)
      context->work.peak_limb_bytes=context->work.live_limb_bytes;
  }
  return status;
}
static void point_clear(certified_scalar_context *context,exact_dyadic *value) {
  if (value->limbs) context->work.live_limb_bytes-=value->capacity*sizeof(uint32_t);
  exact_clear(value);
}
exact_status bound_init(certified_scalar_context *context,directed_interval *value) {
  memset(value,0,sizeof(*value)); exact_status status=point_init(context,&value->lower);
  if (status==EXACT_OK) status=point_init(context,&value->upper);
  if (status!=EXACT_OK) bound_clear(context,value);
  return status;
}
void bound_clear(certified_scalar_context *context,directed_interval *value) {
  point_clear(context,&value->lower); point_clear(context,&value->upper);
}
exact_status bound_copy(directed_interval *out,const directed_interval *in) {
  exact_status status=exact_copy(&out->lower,&in->lower);
  if (status==EXACT_OK) status=exact_copy(&out->upper,&in->upper);
  return status;
}
exact_status bound_integer(directed_interval *out,int64_t value) {
  exact_status status=exact_set(&out->lower,value,0);
  if (status==EXACT_OK) status=exact_set(&out->upper,value,0);
  return status;
}
exact_status scalar_point_product(certified_scalar_context *context,exact_dyadic *out,
                                   const exact_dyadic *left,const exact_dyadic *right) {
  if (!exact_valid(out) || !exact_valid(left) || !exact_valid(right)
      || exact_alias_invalid(out,left) || exact_alias_invalid(out,right)
      || exact_alias_invalid(left,right)) return EXACT_INVALID;
  if (left->binary_scale>SIZE_MAX-right->binary_scale) return EXACT_CAPACITY;
  exact_dyadic result={0}; exact_status status=point_init(context,&result);
  if (status!=EXACT_OK) return status;
  ++context->work.products;
  if (left->length && right->length) {
    if (right->length>CERTIFIED_LIMBS || left->length>CERTIFIED_LIMBS-right->length) {
      status=EXACT_CAPACITY; goto done;
    }
    result.length=left->length+right->length; result.sign=left->sign*right->sign;
    result.binary_scale=left->binary_scale+right->binary_scale;
    for (size_t first=0;first<left->length;++first) {
      uint64_t carry=0;
      for (size_t second=0;second<right->length;++second) {
        size_t destination=first+second;
        uint64_t value=(uint64_t)left->limbs[first]*right->limbs[second]+result.limbs[destination]+carry;
        result.limbs[destination]=(uint32_t)value; carry=value>>32;
      }
      result.limbs[first+right->length]=(uint32_t)carry;
    }
    exact_normalize(&result);
  }
  status=exact_copy(out,&result);
done:
  point_clear(context,&result); return status;
}
exact_status scalar_round(certified_scalar_context *context,exact_dyadic *out,
                           const exact_dyadic *in,unsigned scale,int upward) {
  exact_dyadic result={0},unit={0}; exact_status status=EXACT_OK;
  TRY(point_init(context,&result)); TRY(point_init(context,&unit));
  TRY(exact_truncate(&result,in,scale));
  int comparison; TRY(exact_compare(&comparison,&result,in));
  if (comparison && ((in->sign>0 && upward) || (in->sign<0 && !upward))) {
    TRY(exact_set(&unit,in->sign,scale)); TRY(exact_add(&result,&result,&unit));
  }
  TRY(exact_copy(out,&result));
done:
  point_clear(context,&result); point_clear(context,&unit); return status;
}
exact_status scalar_divide(certified_scalar_context *context,exact_dyadic *out,
                            const exact_dyadic *in,uint32_t divisor,int upward) {
  if (!divisor || !exact_valid(in) || in->binary_scale>context->working_precision) return EXACT_INVALID;
  exact_dyadic result={0},unit={0}; exact_status status=EXACT_OK;
  TRY(point_init(context,&result)); TRY(point_init(context,&unit));
  TRY(exact_magnitude_shift(&result,in,context->working_precision-in->binary_scale));
  uint64_t residue=0;
  for (size_t index=result.length;index;--index) {
    uint64_t word=(residue<<32)|result.limbs[index-1];
    result.limbs[index-1]=(uint32_t)(word/divisor); residue=word%divisor;
  }
  result.sign=in->sign; result.binary_scale=context->working_precision; exact_normalize(&result);
  ++context->work.divisions;
  if (residue && ((in->sign>0 && upward) || (in->sign<0 && !upward))) {
    TRY(exact_set(&unit,in->sign,context->working_precision)); TRY(exact_add(&result,&result,&unit));
  }
  TRY(exact_copy(out,&result));
done:
  point_clear(context,&result); point_clear(context,&unit); return status;
}
exact_status bound_add(certified_scalar_context *context,directed_interval *out,
                        const directed_interval *left,const directed_interval *right,int subtract) {
  directed_interval result={0}; exact_status status=bound_init(context,&result);
  if (status!=EXACT_OK) return status;
  TRY(subtract ? exact_subtract(&result.lower,&left->lower,&right->upper)
               : exact_add(&result.lower,&left->lower,&right->lower));
  TRY(subtract ? exact_subtract(&result.upper,&left->upper,&right->lower)
               : exact_add(&result.upper,&left->upper,&right->upper));
  TRY(bound_copy(out,&result));
done:
  bound_clear(context,&result); return status;
}
exact_status bound_product(certified_scalar_context *context,directed_interval *out,
                            const directed_interval *left,const directed_interval *right) {
  directed_interval result={0}; exact_dyadic products[4]={{0}}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&result));
  for (unsigned index=0;index<4;++index) {
    TRY(point_init(context,&products[index]));
    TRY(scalar_point_product(context,&products[index],index/2 ? &left->upper : &left->lower,
                              index%2 ? &right->upper : &right->lower));
  }
  unsigned least=0,greatest=0;
  for (unsigned index=1;index<4;++index) {
    int comparison; TRY(exact_compare(&comparison,&products[index],&products[least]));
    if (comparison<0) least=index;
    TRY(exact_compare(&comparison,&products[index],&products[greatest]));
    if (comparison>0) greatest=index;
  }
  TRY(scalar_round(context,&result.lower,&products[least],context->working_precision,0));
  TRY(scalar_round(context,&result.upper,&products[greatest],context->working_precision,1));
  TRY(bound_copy(out,&result));
done:
  bound_clear(context,&result);
  for (unsigned index=0;index<4;++index) point_clear(context,&products[index]);
  return status;
}
exact_status bound_scale(certified_scalar_context *context,directed_interval *out,
                          const directed_interval *in,uint32_t numerator,uint32_t denominator) {
  directed_interval result={0}; exact_dyadic multiplier={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&result)); TRY(point_init(context,&multiplier));
  TRY(exact_set(&multiplier,numerator,0));
  TRY(scalar_point_product(context,&result.lower,&in->lower,&multiplier));
  TRY(scalar_point_product(context,&result.upper,&in->upper,&multiplier));
  TRY(scalar_divide(context,&result.lower,&result.lower,denominator,0));
  TRY(scalar_divide(context,&result.upper,&result.upper,denominator,1));
  TRY(bound_copy(out,&result));
done:
  bound_clear(context,&result); point_clear(context,&multiplier); return status;
}
exact_status bound_divide_power(certified_scalar_context *context,directed_interval *out,
                                 const directed_interval *in,unsigned power) {
  directed_interval result={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&result)); TRY(bound_copy(&result,in));
  for (unsigned shift=0;shift<power;++shift) {
    TRY(exact_half(&result.lower,&result.lower)); TRY(exact_half(&result.upper,&result.upper));
  }
  TRY(scalar_round(context,&result.lower,&result.lower,context->working_precision,0));
  TRY(scalar_round(context,&result.upper,&result.upper,context->working_precision,1));
  TRY(bound_copy(out,&result));
done:
  bound_clear(context,&result); return status;
}
