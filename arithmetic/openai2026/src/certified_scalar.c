#include "certified_internal.h"
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static exact_status alternating_tail(directed_interval *sum,const directed_interval *next,unsigned terms) {
  return terms%2 ? exact_subtract(&sum->lower,&sum->lower,&next->upper)
                 : exact_add(&sum->upper,&sum->upper,&next->upper);
}
static exact_status arctangent(certified_scalar_context *context,unsigned denominator,directed_interval *out) {
  directed_interval term={0},sum={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&term)); TRY(bound_init(context,&sum));
  TRY(bound_integer(&term,1)); TRY(bound_scale(context,&term,&term,1,denominator));
  unsigned count=(context->working_precision+7)/4+1;
  for (unsigned index=0;index<count;++index) {
    TRY(bound_add(context,&sum,&sum,&term,index%2));
    TRY(bound_scale(context,&term,&term,2*index+1,denominator*denominator*(2*index+3)));
    ++context->work.series_terms;
  }
  TRY(alternating_tail(&sum,&term,count)); TRY(bound_copy(out,&sum));
  context->pi_terms=count;
done:
  bound_clear(context,&term); bound_clear(context,&sum); return status;
}
static exact_status logarithm_two(certified_scalar_context *context,directed_interval *out) {
  directed_interval term={0},sum={0},tail={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&term)); TRY(bound_init(context,&sum)); TRY(bound_init(context,&tail));
  TRY(bound_integer(&term,1)); TRY(bound_scale(context,&term,&term,1,3));
  unsigned count=(context->working_precision+5)/3+1;
  for (unsigned index=0;index<count;++index) {
    TRY(bound_add(context,&sum,&sum,&term,0));
    TRY(bound_scale(context,&term,&term,2*index+1,9*(2*index+3)));
    ++context->work.series_terms;
  }
  TRY(exact_copy(&tail.upper,&term.upper));
  TRY(bound_scale(context,&tail,&tail,9,8));
  TRY(bound_add(context,&sum,&sum,&tail,0)); TRY(bound_scale(context,out,&sum,2,1));
  context->log_terms=count;
done:
  bound_clear(context,&term); bound_clear(context,&sum); bound_clear(context,&tail); return status;
}
static exact_status narrow(certified_scalar_context *context,const directed_interval *value,unsigned margin) {
  directed_interval width={0}; exact_status status=EXACT_OK; int comparison;
  TRY(bound_init(context,&width)); TRY(exact_subtract(&width.lower,&value->upper,&value->lower));
  TRY(exact_set(&width.upper,1,context->precision+margin));
  TRY(exact_compare(&comparison,&width.lower,&width.upper));
  if (comparison>=0) status=EXACT_CAPACITY;
done:
  bound_clear(context,&width); return status;
}
exact_status certified_scalar_init(certified_scalar_context *context,unsigned precision) {
  if (!context) return EXACT_INVALID;
  memset(context,0,sizeof(*context));
  if (precision<101 || precision>256) return EXACT_INVALID;
  context->precision=precision; context->working_precision=precision+64;
  directed_interval first={0},second={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&context->pi)); TRY(bound_init(context,&context->log_two));
  TRY(bound_init(context,&first)); TRY(bound_init(context,&second));
  TRY(arctangent(context,5,&first)); TRY(arctangent(context,239,&second));
  TRY(bound_scale(context,&first,&first,16,1)); TRY(bound_scale(context,&second,&second,4,1));
  TRY(bound_add(context,&context->pi,&first,&second,1));
  TRY(logarithm_two(context,&context->log_two));
  TRY(narrow(context,&context->pi,32)); TRY(narrow(context,&context->log_two,32));
  TRY(bound_integer(&first,3)); TRY(bound_integer(&second,4));
  int comparison; TRY(exact_compare(&comparison,&context->pi.lower,&first.lower));
  if (comparison<=0) { status=EXACT_INVALID; goto done; }
  TRY(exact_compare(&comparison,&context->pi.upper,&second.upper));
  if (comparison>=0) { status=EXACT_INVALID; goto done; }
  TRY(exact_set(&first.lower,1,1)); TRY(exact_set(&second.upper,1,0));
  TRY(exact_compare(&comparison,&context->log_two.lower,&first.lower));
  if (comparison<=0) { status=EXACT_INVALID; goto done; }
  TRY(exact_compare(&comparison,&context->log_two.upper,&second.upper));
  if (comparison>=0) status=EXACT_INVALID;
done:
  bound_clear(context,&first); bound_clear(context,&second);
  if (status!=EXACT_OK) certified_scalar_clear(context);
  return status;
}
void certified_scalar_clear(certified_scalar_context *context) {
  if (context) { bound_clear(context,&context->pi); bound_clear(context,&context->log_two); memset(context,0,sizeof(*context)); }
}
static int valid_context(const certified_scalar_context *context) {
  return context && context->precision>=101 && context->precision<=256
    && context->working_precision==context->precision+64
    && exact_valid(&context->pi.lower) && exact_valid(&context->pi.upper)
    && exact_valid(&context->log_two.lower) && exact_valid(&context->log_two.upper);
}
static int valid_output(const certified_scalar_context *context,const exact_dyadic *out,const scalar_certificate *certificate) {
  if (!exact_valid(out) || !certificate) return 0;
  const exact_dyadic *constants[]={&context->pi.lower,&context->pi.upper,&context->log_two.lower,&context->log_two.upper};
  for (unsigned index=0;index<4;++index)
    if (exact_overlap(certificate,sizeof(*certificate),constants[index]->limbs,constants[index]->capacity*sizeof(uint32_t))
        || exact_overlap(out,sizeof(*out),constants[index]->limbs,constants[index]->capacity*sizeof(uint32_t))) return 0;
  return exact_valid(out) && certificate
    && !exact_overlap(out,sizeof(*out),context,sizeof(*context))
    && !exact_overlap(certificate,sizeof(*certificate),context,sizeof(*context))
    && !exact_overlap(certificate,sizeof(*certificate),out,sizeof(*out))
    && !exact_overlap(certificate,sizeof(*certificate),out->limbs,out->capacity*sizeof(uint32_t))
    && !exact_overlap(out->limbs,out->capacity*sizeof(uint32_t),context,sizeof(*context))
    && !exact_alias_invalid(out,&context->pi.lower) && !exact_alias_invalid(out,&context->pi.upper)
    && !exact_alias_invalid(out,&context->log_two.lower) && !exact_alias_invalid(out,&context->log_two.upper);
}
static exact_status negative_exponential(certified_scalar_context *context,const directed_interval *argument,
                                          directed_interval *out,unsigned *range_shifts) {
  if (argument->lower.sign<0) return EXACT_INVALID;
  directed_interval multiplier={0},remainder={0},term={0},sum={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&multiplier)); TRY(bound_init(context,&remainder));
  TRY(bound_init(context,&term)); TRY(bound_init(context,&sum));
  unsigned lower=0,upper=8*context->precision+1;
  while (upper-lower>1) {
    unsigned middle=(lower+upper)/2; int comparison;
    TRY(bound_scale(context,&multiplier,&context->log_two,middle,1));
    TRY(exact_compare(&comparison,&multiplier.upper,&argument->lower));
    if (comparison<=0) lower=middle; else upper=middle;
  }
  TRY(bound_scale(context,&multiplier,&context->log_two,lower,1));
  TRY(bound_add(context,&remainder,argument,&multiplier,1));
  TRY(bound_scale(context,&multiplier,&context->log_two,2,1));
  int comparison; TRY(exact_compare(&comparison,&remainder.upper,&multiplier.upper));
  if (remainder.lower.sign<0 || comparison>0) { status=EXACT_CAPACITY; goto done; }
  TRY(bound_integer(&term,1));
  unsigned count=context->working_precision+16;
#ifdef MUTANT_RELAXED_TAIL
  count=2;
#endif
  for (unsigned index=0;index<count;++index) {
    TRY(bound_add(context,&sum,&sum,&term,index%2));
    TRY(bound_product(context,&term,&term,&remainder));
    TRY(bound_scale(context,&term,&term,1,index+1));
    ++context->work.series_terms;
  }
#ifndef MUTANT_RELAXED_TAIL
  TRY(alternating_tail(&sum,&term,count));
#endif
  if (sum.lower.sign<0) { status=EXACT_CAPACITY; goto done; }
  TRY(bound_divide_power(context,out,&sum,lower)); TRY(narrow(context,out,16));
  *range_shifts=lower;
done:
  bound_clear(context,&multiplier); bound_clear(context,&remainder);
  bound_clear(context,&term); bound_clear(context,&sum); return status;
}
exact_status certified_exponential(certified_scalar_context *context,uint32_t j,uint32_t k,
                                     int positive,unsigned binary_scale,exact_dyadic *out,
                                     scalar_certificate *certificate) {
  if (!valid_context(context) || !valid_output(context,out,certificate) || !k
      || (positive!=0 && positive!=1) || (!positive && binary_scale)
      || binary_scale>2*context->precision) return EXACT_INVALID;
  scalar_certificate proof={context->precision,context->working_precision,0,0,2,0};
  directed_interval argument={0},multiple={0},result={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&argument)); TRY(bound_init(context,&multiple)); TRY(bound_init(context,&result));
  if (!positive && (uint64_t)j>(uint64_t)k*context->precision) {
    TRY(bound_integer(&result,0)); proof.early_zero=1;
  } else {
    TRY(bound_scale(context,&argument,&context->pi,j,k));
    if (positive) {
      TRY(bound_scale(context,&multiple,&context->log_two,binary_scale,1));
      TRY(bound_add(context,&argument,&multiple,&argument,1));
      if (argument.lower.sign<0) { status=EXACT_INVALID; goto done; }
    }
    TRY(negative_exponential(context,&argument,&result,&proof.range_shifts));
    proof.series_terms=context->working_precision+16;
  }
  TRY(exact_truncate(&result.lower,&result.lower,context->precision));
  TRY(bound_integer(&multiple,1)); int comparison;
  TRY(exact_compare(&comparison,&result.lower,&multiple.upper));
  if (comparison>0 || result.lower.sign<0) { status=EXACT_INVALID; goto done; }
#ifdef MUTANT_ZERO
  TRY(exact_set(&result.lower,0,0));
#endif
  TRY(exact_copy(out,&result.lower)); *certificate=proof;
done:
  bound_clear(context,&argument); bound_clear(context,&multiple); bound_clear(context,&result); return status;
}
static void negate_interval(directed_interval *value) {
  exact_dyadic temporary=value->lower; value->lower=value->upper; value->upper=temporary;
  value->lower.sign=-value->lower.sign; value->upper.sign=-value->upper.sign;
}
static void rotate_intervals(directed_interval *real,directed_interval *imaginary,unsigned quarter) {
  for (unsigned turn=0;turn<(quarter&3);++turn) {
    directed_interval temporary=*real; *real=*imaginary; *imaginary=temporary; negate_interval(real);
  }
}
static exact_status sine_cosine(certified_scalar_context *context,const directed_interval *argument,
                                 directed_interval *cosine,directed_interval *sine,unsigned *terms) {
  directed_interval square={0},cos_term={0},sin_term={0}; exact_status status=EXACT_OK;
  TRY(bound_init(context,&square)); TRY(bound_init(context,&cos_term)); TRY(bound_init(context,&sin_term));
  TRY(bound_product(context,&square,argument,argument));
  TRY(bound_integer(&cos_term,1)); TRY(bound_copy(&sin_term,argument));
  unsigned count=(context->working_precision+7)/2+1;
  for (unsigned index=0;index<count;++index) {
    TRY(bound_add(context,cosine,cosine,&cos_term,index%2));
    TRY(bound_add(context,sine,sine,&sin_term,index%2));
    TRY(bound_product(context,&cos_term,&cos_term,&square));
    TRY(bound_scale(context,&cos_term,&cos_term,1,(2*index+1)*(2*index+2)));
    TRY(bound_product(context,&sin_term,&sin_term,&square));
    TRY(bound_scale(context,&sin_term,&sin_term,1,(2*index+2)*(2*index+3)));
    context->work.series_terms+=2;
  }
  TRY(alternating_tail(cosine,&cos_term,count)); TRY(alternating_tail(sine,&sin_term,count));
  *terms=2*count;
done:
  bound_clear(context,&square); bound_clear(context,&cos_term); bound_clear(context,&sin_term); return status;
}
static exact_status midpoint(exact_dyadic *out,const directed_interval *in,unsigned precision) {
  exact_status status=exact_add(out,&in->lower,&in->upper);
  if (status==EXACT_OK) status=exact_half(out,out);
  if (status==EXACT_OK) status=exact_truncate(out,out,precision);
  return status;
}
static exact_status maximum_distance(exact_dyadic *out,const exact_dyadic *point,
                                      const directed_interval *reference,exact_dyadic *temporary) {
  exact_status status=exact_subtract(out,point,&reference->lower);
  if (status!=EXACT_OK) return status;
  if (out->sign<0) out->sign=1;
  status=exact_subtract(temporary,point,&reference->upper);
  if (status!=EXACT_OK) return status;
  if (temporary->sign<0) temporary->sign=1;
  int comparison; status=exact_compare(&comparison,out,temporary);
  if (status==EXACT_OK && comparison<0) status=exact_copy(out,temporary);
  return status;
}
exact_status certified_root(certified_scalar_context *context,uint32_t j,uint32_t k,
                              exact_gaussian *out,scalar_certificate *certificate) {
  if (!valid_context(context) || !out || k<=1 || j>=k
      || !valid_output(context,&out->real,certificate) || !valid_output(context,&out->imaginary,certificate)
      || exact_alias_invalid(&out->real,&out->imaginary)) return EXACT_INVALID;
  directed_interval argument={0},radial={0},real={0},imaginary={0},analytic_real={0},analytic_imaginary={0};
  directed_interval result={0},metric={0},limit={0}; exact_status status=EXACT_OK;
  scalar_certificate proof={context->precision,context->working_precision,0,0,2,0};
  TRY(bound_init(context,&argument)); TRY(bound_init(context,&radial));
  TRY(bound_init(context,&real)); TRY(bound_init(context,&imaginary));
  TRY(bound_init(context,&analytic_real)); TRY(bound_init(context,&analytic_imaginary));
  TRY(bound_init(context,&result)); TRY(bound_init(context,&metric)); TRY(bound_init(context,&limit));
  unsigned quarter=(unsigned)(((uint64_t)8*j+k)/((uint64_t)2*k));
  int64_t numerator=(int64_t)4*j-(int64_t)quarter*k;
  uint32_t magnitude=(uint32_t)(numerator<0 ? -numerator : numerator);
  TRY(bound_scale(context,&argument,&context->pi,magnitude,k));
  TRY(bound_divide_power(context,&argument,&argument,1));
  TRY(sine_cosine(context,&argument,&real,&imaginary,&proof.series_terms));
  if (numerator<0) negate_interval(&imaginary);
  rotate_intervals(&real,&imaginary,quarter);
  TRY(bound_copy(&analytic_real,&real)); TRY(bound_copy(&analytic_imaginary,&imaginary));
  /* Lemma 2.12's inward exponential, computed with additional guard bits. */
  TRY(exact_set(&argument.lower,1,context->precision+2));
  TRY(exact_copy(&argument.upper,&argument.lower));
  TRY(negative_exponential(context,&argument,&radial,&proof.range_shifts));
  proof.series_terms+=context->working_precision+16;
  TRY(bound_product(context,&real,&real,&radial)); TRY(bound_product(context,&imaginary,&imaginary,&radial));
  TRY(midpoint(&result.lower,&real,context->precision)); TRY(midpoint(&result.upper,&imaginary,context->precision));
  TRY(scalar_point_product(context,&metric.lower,&result.lower,&result.lower));
  TRY(scalar_point_product(context,&metric.upper,&result.upper,&result.upper));
  TRY(exact_add(&metric.lower,&metric.lower,&metric.upper)); TRY(bound_integer(&limit,1));
  int comparison; TRY(exact_compare(&comparison,&metric.lower,&limit.lower));
  if (comparison>0) { status=EXACT_CAPACITY; goto done; }
  TRY(maximum_distance(&metric.lower,&result.lower,&analytic_real,&limit.upper));
  TRY(maximum_distance(&metric.upper,&result.upper,&analytic_imaginary,&limit.upper));
  TRY(scalar_point_product(context,&metric.lower,&metric.lower,&metric.lower));
  TRY(scalar_point_product(context,&metric.upper,&metric.upper,&metric.upper));
  TRY(exact_add(&metric.lower,&metric.lower,&metric.upper)); TRY(exact_set(&limit.lower,4,2*context->precision));
  TRY(exact_compare(&comparison,&metric.lower,&limit.lower));
  if (comparison>=0) { status=EXACT_CAPACITY; goto done; }
  if (result.lower.length>out->real.capacity || result.upper.length>out->imaginary.capacity) { status=EXACT_CAPACITY; goto done; }
#ifdef MUTANT_ZERO
  TRY(bound_integer(&result,0));
#endif
  TRY(exact_copy(&out->real,&result.lower)); TRY(exact_copy(&out->imaginary,&result.upper)); *certificate=proof;
done:
  bound_clear(context,&argument); bound_clear(context,&radial);
  bound_clear(context,&real); bound_clear(context,&imaginary);
  bound_clear(context,&analytic_real); bound_clear(context,&analytic_imaginary);
  bound_clear(context,&result); bound_clear(context,&metric); bound_clear(context,&limit); return status;
}
