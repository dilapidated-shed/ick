#include "certified_internal.h"
#include <stdlib.h>
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
struct resampling_plan {
  resampling_parameters parameters;
  certified_scalar_context scalar;
  exact_dyadic *gaussian,*error,*diagonal;
  unsigned *gaussian_source,*error_source,*gaussian_start;
  size_t gaussian_count,error_count;
  resampling_work work;
};
static unsigned gcd(unsigned first,unsigned second) {
  while (second) { unsigned residue=first%second; first=second; second=residue; }
  return first;
}
unsigned resampling_nearest(const resampling_parameters *parameters,unsigned index) {
  if (!parameters || parameters->source_length<2 || parameters->target_length<=parameters->source_length
      || parameters->target_length>64 || index>=parameters->source_length) return UINT32_MAX;
  unsigned quotient=parameters->target_length*index/parameters->source_length;
  unsigned residue=parameters->target_length*index%parameters->source_length;
#ifdef MUTANT_TIE
  return quotient+(2*residue>parameters->source_length);
#else
  return quotient+(2*residue>=parameters->source_length);
#endif
}
exact_status resampling_admit(unsigned precision,unsigned source,unsigned target,unsigned alpha,
                               uint64_t coefficient_budget,resampling_parameters *out) {
  if (!out || precision<=100 || source<2 || target<=source || alpha<2 || alpha>15
      || alpha*alpha>=precision || gcd(source,target)!=1) return EXACT_INVALID;
  if (precision>256 || target>64) return EXACT_CAPACITY;
  uint64_t fourth=(uint64_t)alpha*alpha*alpha*alpha;
  if ((uint64_t)(target-source)*fourth<=(uint64_t)precision*source) return EXACT_INVALID;
  unsigned square_root=1; while (square_root*square_root<precision) ++square_root;
  unsigned error_radius=1; while ((2*alpha*error_radius)*(2*alpha*error_radius)<precision) ++error_radius;
  resampling_parameters parameters={precision,source,target,alpha,square_root*alpha,error_radius,
    (precision*source+alpha*alpha*(target-source)-1)/(alpha*alpha*(target-source))};
  uint64_t coefficients=2*(uint64_t)parameters.gaussian_radius*target+2*(uint64_t)error_radius*source+source;
  if (coefficients>coefficient_budget || coefficients>65536) return EXACT_CAPACITY;
  if (14*parameters.gaussian_radius+1>=16*precision || 8*error_radius+3>=precision/3
      || parameters.neumann_terms>precision) return EXACT_INVALID;
  *out=parameters; return EXACT_OK;
}
static exact_status storage_init(resampling_plan *plan,exact_dyadic *value) {
  exact_status status=exact_init(value,16);
  if (status==EXACT_OK) plan->work.allocated_limb_bytes+=16*sizeof(uint32_t);
  return status;
}
static exact_status grid_product(resampling_plan *plan,exact_dyadic *out,
                                  const exact_dyadic *first,const exact_dyadic *second) {
  exact_status status=scalar_point_product(&plan->scalar,out,first,second);
  if (status==EXACT_OK) status=exact_truncate(out,out,plan->parameters.precision);
  ++plan->work.ram_products; return status;
}
exact_status resampling_prepare(const resampling_parameters *parameters,uint64_t budget,resampling_plan **out) {
  if (!parameters || !out || *out) return EXACT_INVALID;
  resampling_parameters checked;
  exact_status status=resampling_admit(parameters->precision,parameters->source_length,parameters->target_length,parameters->alpha,budget,&checked);
  if (status!=EXACT_OK) return status;
  if (memcmp(&checked,parameters,sizeof(checked))) return EXACT_INVALID;
  resampling_plan *plan=calloc(1,sizeof(*plan)); if (!plan) return EXACT_ALLOCATION;
  plan->parameters=*parameters;
  unsigned source=parameters->source_length,target=parameters->target_length,alpha=parameters->alpha;
  size_t maximum_gaussians=2*(size_t)parameters->gaussian_radius*target;
  plan->error_count=2*(size_t)parameters->error_radius*source;
  exact_dyadic beta={0},weight={0};
  TRY(certified_scalar_init(&plan->scalar,parameters->precision));
  plan->gaussian=calloc(maximum_gaussians,sizeof(*plan->gaussian));
  plan->error=calloc(plan->error_count,sizeof(*plan->error));
  plan->diagonal=calloc(source,sizeof(*plan->diagonal));
  plan->gaussian_source=calloc(maximum_gaussians,sizeof(unsigned));
  plan->error_source=calloc(plan->error_count,sizeof(unsigned));
  plan->gaussian_start=calloc(target+1,sizeof(unsigned));
  if (!plan->gaussian || !plan->error || !plan->diagonal || !plan->gaussian_source || !plan->error_source || !plan->gaussian_start) {
    status=EXACT_ALLOCATION; goto done;
  }
  plan->work.allocated_descriptor_bytes=sizeof(*plan)+(maximum_gaussians+plan->error_count+source)*sizeof(exact_dyadic)
    +(maximum_gaussians+plan->error_count+target+1)*sizeof(unsigned);
  TRY(exact_init(&beta,32)); TRY(exact_init(&weight,32)); TRY(exact_set(&beta,1,0));
  TRY(scalar_divide(&plan->scalar,&beta,&beta,2*alpha,0)); TRY(exact_truncate(&beta,&beta,parameters->precision));
  for (unsigned row=0;row<target;++row) {
    plan->gaussian_start[row]=(unsigned)plan->gaussian_count;
    unsigned dilation_numerator=source,dilation_denominator=target;
#ifdef MUTANT_DILATION
    dilation_numerator=target; dilation_denominator=source;
#endif
    int middle=(int)(dilation_numerator*row/dilation_denominator),radius=(int)parameters->gaussian_radius;
    for (int index=middle-radius;index<=middle+radius;++index) {
      int64_t difference=(int64_t)index*dilation_denominator-(int64_t)dilation_numerator*row;
      uint64_t distance=(uint64_t)(difference<0 ? -difference : difference);
      if (distance>=(uint64_t)parameters->gaussian_radius*dilation_denominator) continue;
      if (plan->gaussian_count==maximum_gaussians) { status=EXACT_CAPACITY; goto done; }
      unsigned numerator=(unsigned)(distance*distance),denominator=alpha*alpha*dilation_denominator*dilation_denominator;
      scalar_certificate certificate;
      TRY(certified_exponential(&plan->scalar,numerator,denominator,0,0,&weight,&certificate));
      size_t slot=plan->gaussian_count++;
      TRY(storage_init(plan,&plan->gaussian[slot])); TRY(grid_product(plan,&plan->gaussian[slot],&beta,&weight));
      int residue=index%(int)source; if (residue<0) residue+=(int)source;
      plan->gaussian_source[slot]=(unsigned)residue;
    }
  }
  plan->gaussian_start[target]=(unsigned)plan->gaussian_count;
  for (unsigned row=0;row<source;++row) {
    int64_t beta_numerator=(int64_t)target*row-(int64_t)source*resampling_nearest(parameters,row);
    for (int offset=-(int)parameters->error_radius;offset<=(int)parameters->error_radius;++offset) if (offset) {
      int next=((int)row+offset)%(int)source; if (next<0) next+=(int)source;
      int64_t next_beta=(int64_t)target*next-(int64_t)source*resampling_nearest(parameters,(unsigned)next);
      int64_t stretched=(int64_t)target*offset+beta_numerator;
      int64_t numerator=(stretched*stretched-next_beta*next_beta)*(int64_t)alpha*alpha;
      if (numerator<0 || (uint64_t)numerator>UINT32_MAX) { status=EXACT_INVALID; goto done; }
      unsigned local=offset<0 ? (unsigned)(offset+(int)parameters->error_radius)
                             : parameters->error_radius+(unsigned)offset-1;
      size_t slot=row*(2*parameters->error_radius)+local;
      scalar_certificate certificate; TRY(storage_init(plan,&plan->error[slot]));
      TRY(certified_exponential(&plan->scalar,(uint32_t)numerator,source*source,0,0,&plan->error[slot],&certificate));
      plan->error_source[slot]=(unsigned)next;
    }
    scalar_certificate certificate; TRY(storage_init(plan,&plan->diagonal[row]));
    TRY(certified_exponential(&plan->scalar,(uint32_t)(alpha*alpha*beta_numerator*beta_numerator),source*source,
                              1,2*alpha*alpha-2,&plan->diagonal[row],&certificate));
  }
  plan->work.coefficient_count=plan->gaussian_count+plan->error_count+source;
  *out=plan; plan=NULL;
done:
  exact_clear(&beta); exact_clear(&weight); resampling_clear(plan); return status;
}
void resampling_clear(resampling_plan *plan) {
  if (!plan) return;
  if (plan->gaussian) for (size_t index=0;index<plan->gaussian_count;++index) exact_clear(&plan->gaussian[index]);
  if (plan->error) for (size_t index=0;index<plan->error_count;++index) exact_clear(&plan->error[index]);
  if (plan->diagonal) for (unsigned index=0;index<plan->parameters.source_length;++index) exact_clear(&plan->diagonal[index]);
  free(plan->gaussian); free(plan->error); free(plan->diagonal); free(plan->gaussian_source); free(plan->error_source); free(plan->gaussian_start);
  certified_scalar_clear(&plan->scalar); free(plan);
}
static exact_dyadic *channel(exact_gaussian *value,unsigned component) {
  return component ? &value->imaginary : &value->real;
}
static const exact_dyadic *const_channel(const exact_gaussian *value,unsigned component) {
  return component ? &value->imaginary : &value->real;
}
static exact_status vector_init(exact_gaussian **out,size_t length) {
  exact_gaussian *values=calloc(length,sizeof(*values)); if (!values) return EXACT_ALLOCATION;
  exact_status status=EXACT_OK;
  for (size_t index=0;index<length && status==EXACT_OK;++index) for (unsigned component=0;component<2 && status==EXACT_OK;++component)
    status=exact_init(channel(&values[index],component),32);
  *out=values; return status;
}
static void vector_clear(exact_gaussian *values,size_t length) {
  if (!values) return;
  for (size_t index=0;index<length;++index) { exact_clear(&values[index].real); exact_clear(&values[index].imaginary); }
  free(values);
}
static exact_status disk(resampling_plan *plan,const exact_gaussian *value) {
  exact_dyadic real={0},imaginary={0},one={0}; exact_status status=EXACT_OK; int comparison;
  TRY(exact_init(&real,32)); TRY(exact_init(&imaginary,32)); TRY(exact_init(&one,32));
  TRY(scalar_point_product(&plan->scalar,&real,&value->real,&value->real));
  TRY(scalar_point_product(&plan->scalar,&imaginary,&value->imaginary,&value->imaginary));
  TRY(exact_add(&real,&real,&imaginary)); TRY(exact_set(&one,1,0)); TRY(exact_compare(&comparison,&real,&one));
  if (comparison>0) status=EXACT_INVALID;
done:
  exact_clear(&real); exact_clear(&imaginary); exact_clear(&one); return status;
}
static exact_status buffers(resampling_plan *plan,const exact_gaussian *in,size_t input_length,
                              exact_gaussian *out,size_t output_length) {
  if (!plan || !in || !out || exact_overlap(in,input_length*sizeof(*in),out,output_length*sizeof(*out))) return EXACT_INVALID;
  for (size_t index=0;index<2*(input_length+output_length);++index) {
    const exact_dyadic *value=index<2*input_length ? const_channel(&in[index/2],index%2)
                                                 : const_channel(&out[(index-2*input_length)/2],index%2);
    if (!exact_valid(value) || (index<2*input_length && value->binary_scale>plan->parameters.precision)) return EXACT_INVALID;
    for (size_t earlier=0;earlier<index;++earlier) {
      const exact_dyadic *other=earlier<2*input_length ? const_channel(&in[earlier/2],earlier%2)
                                                     : const_channel(&out[(earlier-2*input_length)/2],earlier%2);
      if (exact_alias_invalid(value,other)) return EXACT_INVALID;
    }
  }
  for (size_t index=0;index<input_length;++index) {
    exact_status status=disk(plan,&in[index]); if (status!=EXACT_OK) return status;
  }
  return EXACT_OK;
}
static exact_status commit(resampling_plan *plan,exact_gaussian *out,const exact_gaussian *in,size_t length) {
  for (size_t index=0;index<length;++index) for (unsigned component=0;component<2;++component)
    if (const_channel(&in[index],component)->length>channel(&out[index],component)->capacity) return EXACT_CAPACITY;
  for (size_t index=0;index<length;++index) {
    exact_status status=disk(plan,&in[index]); if (status!=EXACT_OK) return status;
  }
  for (size_t index=0;index<length;++index) for (unsigned component=0;component<2;++component)
    (void)exact_copy(channel(&out[index],component),const_channel(&in[index],component));
  ++plan->work.line_calls; return EXACT_OK;
}
exact_status resampling_A(resampling_plan *plan,const exact_gaussian *in,size_t input_length,exact_gaussian *out,size_t output_length) {
  if (!plan || input_length!=plan->parameters.source_length || output_length!=plan->parameters.target_length) return EXACT_INVALID;
  exact_status status=buffers(plan,in,input_length,out,output_length);
  if (status!=EXACT_OK) return status;
  exact_gaussian *result=NULL; exact_dyadic temporary={0};
  TRY(vector_init(&result,output_length)); TRY(exact_init(&temporary,32));
  for (size_t row=0;row<output_length;++row) for (unsigned index=plan->gaussian_start[row];index<plan->gaussian_start[row+1];++index)
    for (unsigned component=0;component<2;++component) {
      TRY(grid_product(plan,&temporary,&plan->gaussian[index],const_channel(&in[plan->gaussian_source[index]],component)));
      TRY(exact_add(channel(&result[row],component),channel(&result[row],component),&temporary));
      ++plan->work.ram_additions;
    }
#ifdef MUTANT_ZERO
  for (size_t row=0;row<output_length;++row) { TRY(exact_set(&result[row].real,0,0)); TRY(exact_set(&result[row].imaginary,0,0)); }
#endif
  TRY(commit(plan,out,result,output_length));
done:
  vector_clear(result,output_length); exact_clear(&temporary); return status;
}
static exact_status apply_error(resampling_plan *plan,const exact_gaussian *in,exact_gaussian *out,exact_dyadic *temporary) {
  for (unsigned row=0;row<plan->parameters.source_length;++row) {
    exact_status status=exact_set(&out[row].real,0,0);
    if (status==EXACT_OK) status=exact_set(&out[row].imaginary,0,0);
    if (status!=EXACT_OK) return status;
    unsigned first=row*(2*plan->parameters.error_radius),last=first+2*plan->parameters.error_radius;
    for (unsigned index=first;index<last;++index) for (unsigned component=0;component<2;++component) {
      status=grid_product(plan,temporary,&plan->error[index],const_channel(&in[plan->error_source[index]],component));
      if (status==EXACT_OK) status=exact_add(channel(&out[row],component),channel(&out[row],component),temporary);
      if (status!=EXACT_OK) return status;
      ++plan->work.ram_additions;
    }
    status=disk(plan,&out[row]); if (status!=EXACT_OK) return status;
  }
  return EXACT_OK;
}
exact_status resampling_B0(resampling_plan *plan,const exact_gaussian *in,size_t input_length,exact_gaussian *out,size_t output_length) {
  if (!plan || input_length!=plan->parameters.target_length || output_length!=plan->parameters.source_length) return EXACT_INVALID;
  exact_status status=buffers(plan,in,input_length,out,output_length);
  if (status!=EXACT_OK) return status;
  exact_gaussian *term=NULL,*next=NULL,*result=NULL; exact_dyadic temporary={0};
  TRY(vector_init(&term,output_length)); TRY(vector_init(&next,output_length)); TRY(vector_init(&result,output_length)); TRY(exact_init(&temporary,32));
  unsigned row=0;
  for (unsigned source_index=0;source_index<input_length;++source_index) {
    ++plan->work.selection_records;
    if (row==output_length || source_index!=resampling_nearest(&plan->parameters,row)) continue;
    for (unsigned component=0;component<2;++component) {
      const exact_dyadic *selected=const_channel(&in[source_index],component);
      TRY(exact_half(channel(&term[row],component),selected));
      TRY(exact_truncate(channel(&term[row],component),channel(&term[row],component),plan->parameters.precision));
      TRY(exact_copy(channel(&result[row],component),channel(&term[row],component)));
    }
    ++row;
  }
  if (row!=output_length) { status=EXACT_INVALID; goto done; }
  for (unsigned iteration=1;iteration<plan->parameters.neumann_terms;++iteration) {
    TRY(apply_error(plan,term,next,&temporary)); exact_gaussian *swap=term; term=next; next=swap;
#ifdef MUTANT_NEUMANN
    if (iteration==1) continue;
#endif
    for (unsigned row=0;row<output_length;++row) for (unsigned component=0;component<2;++component) {
      TRY(iteration%2 ? exact_subtract(channel(&result[row],component),channel(&result[row],component),const_channel(&term[row],component))
                      : exact_add(channel(&result[row],component),channel(&result[row],component),const_channel(&term[row],component)));
      ++plan->work.ram_additions;
    }
  }
  for (unsigned row=0;row<output_length;++row) for (unsigned component=0;component<2;++component)
    TRY(grid_product(plan,channel(&result[row],component),&plan->diagonal[row],channel(&result[row],component)));
#ifdef MUTANT_ZERO
  for (size_t row=0;row<output_length;++row) { TRY(exact_set(&result[row].real,0,0)); TRY(exact_set(&result[row].imaginary,0,0)); }
#endif
  TRY(commit(plan,out,result,output_length));
done:
  vector_clear(term,output_length); vector_clear(next,output_length); vector_clear(result,output_length); exact_clear(&temporary); return status;
}
exact_status resampling_receipt(const resampling_plan *plan,resampling_parameters *parameters,resampling_work *work) {
  if (!plan || !parameters || !work) return EXACT_INVALID;
  *parameters=plan->parameters; *work=plan->work; work->scalar=plan->scalar.work; return EXACT_OK;
}
static size_t box_address(unsigned prefix,unsigned row,unsigned column,unsigned tail,
                           unsigned capacity0,unsigned capacity1,unsigned suffix) {
  return (((size_t)prefix*capacity0+row)*capacity1+column)*suffix+tail;
}
exact_status resampling_tensor(resampling_plan *first,resampling_plan *second,int opposite,
                                 unsigned prefixes,unsigned suffix,unsigned capacity0,unsigned capacity1,
                                 exact_gaussian *box,size_t records) {
  if (!first || !second || !box || first->parameters.precision!=second->parameters.precision
      || (opposite!=0 && opposite!=1) || !prefixes || !suffix || prefixes>4 || suffix>4
      || capacity0<first->parameters.target_length || capacity1<second->parameters.target_length) return EXACT_INVALID;
  if (capacity0>64 || capacity1>64 || records>16384) return EXACT_CAPACITY;
  if (records!=(size_t)prefixes*capacity0*capacity1*suffix) return EXACT_INVALID;
  unsigned active0=opposite ? first->parameters.target_length : first->parameters.source_length;
  unsigned active1=opposite ? second->parameters.target_length : second->parameters.source_length;
  for (size_t index=0;index<2*records;++index) {
    exact_dyadic *value=channel(&box[index/2],index%2);
    if (!exact_valid(value) || value->binary_scale>first->parameters.precision) return EXACT_INVALID;
    for (size_t previous=0;previous<index;++previous)
      if (exact_alias_invalid(value,channel(&box[previous/2],previous%2))) return EXACT_INVALID;
  }
  for (unsigned prefix=0;prefix<prefixes;++prefix) for (unsigned row=0;row<capacity0;++row)
    for (unsigned column=0;column<capacity1;++column) for (unsigned tail=0;tail<suffix;++tail) {
      exact_gaussian *value=&box[box_address(prefix,row,column,tail,capacity0,capacity1,suffix)];
      if ((row>=active0 || column>=active1) && (value->real.length || value->imaginary.length)) return EXACT_INVALID;
      exact_status status=disk(first,value); if (status!=EXACT_OK) return status;
    }
  exact_gaussian *work=NULL,*input=NULL,*output=NULL; exact_status status=EXACT_OK;
  TRY(vector_init(&work,records)); TRY(vector_init(&input,64)); TRY(vector_init(&output,64));
  for (size_t index=0;index<records;++index) for (unsigned component=0;component<2;++component)
    TRY(exact_copy(channel(&work[index],component),const_channel(&box[index],component)));
  for (unsigned step=0;step<2;++step) {
    unsigned axis=opposite ? 1-step : step;
    resampling_plan *plan=axis ? second : first;
    unsigned old_length=opposite ? plan->parameters.target_length : plan->parameters.source_length;
    unsigned new_length=opposite ? plan->parameters.source_length : plan->parameters.target_length;
    unsigned lines=axis ? capacity0 : capacity1,capacity=axis ? capacity1 : capacity0;
    for (unsigned prefix=0;prefix<prefixes;++prefix) for (unsigned line=0;line<lines;++line) for (unsigned tail=0;tail<suffix;++tail) {
      for (unsigned position=0;position<old_length;++position) {
        size_t address=box_address(prefix,axis ? line : position,axis ? position : line,tail,capacity0,capacity1,suffix);
        TRY(exact_copy(&input[position].real,&work[address].real)); TRY(exact_copy(&input[position].imaginary,&work[address].imaginary));
      }
      TRY(opposite ? resampling_B0(plan,input,old_length,output,new_length) : resampling_A(plan,input,old_length,output,new_length));
      for (unsigned position=0;position<capacity;++position) {
        size_t address=box_address(prefix,axis ? line : position,axis ? position : line,tail,capacity0,capacity1,suffix);
        if (position<new_length) {
          TRY(exact_copy(&work[address].real,&output[position].real)); TRY(exact_copy(&work[address].imaginary,&output[position].imaginary));
        } else { TRY(exact_set(&work[address].real,0,0)); TRY(exact_set(&work[address].imaginary,0,0)); }
      }
    }
  }
  TRY(commit(first,box,work,records));
done:
  vector_clear(work,records); vector_clear(input,64); vector_clear(output,64); return status;
}
