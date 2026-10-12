#include "numerical_internal.h"
#include <stdlib.h>
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static exact_dyadic *component(exact_gaussian *value,unsigned imaginary) { return imaginary ? &value->imaginary : &value->real; }
exact_status numerical_values(exact_gaussian **out,size_t length,size_t capacity) {
  *out=calloc(length,sizeof(**out)); if (!*out) return EXACT_ALLOCATION;
  for (size_t index=0;index<length;++index) for (unsigned part=0;part<2;++part) {
    exact_status status=exact_init(component(&(*out)[index],part),capacity); if (status!=EXACT_OK) return status;
  }
  return EXACT_OK;
}
void numerical_clear_values(exact_gaussian *values,size_t length) {
  if (!values) return;
  for (size_t index=0;index<length;++index) { exact_clear(&values[index].real); exact_clear(&values[index].imaginary); }
  free(values);
}
exact_status numerical_copy_value(exact_gaussian *out,const exact_gaussian *input) {
  exact_status status=exact_copy(&out->real,&input->real);
  return status==EXACT_OK ? exact_copy(&out->imaginary,&input->imaginary) : status;
}
exact_status numerical_array_contract(const exact_gaussian *first,const exact_gaussian *second,exact_gaussian *out,size_t length) {
  if (!first || !out || exact_overlap(first,length*sizeof(*first),out,length*sizeof(*out))
      || (second && exact_overlap(second,length*sizeof(*second),out,length*sizeof(*out)))) return EXACT_INVALID;
  unsigned banks=second ? 3 : 2;
  for (size_t index=0;index<banks*2*length;++index) {
    size_t bank=index/(2*length),local=index%(2*length);
    const exact_gaussian *values=bank==banks-1 ? out : bank==0 ? first : second;
    const exact_dyadic *value=component((exact_gaussian *)&values[local/2],local%2);
    if (!exact_valid(value)) return EXACT_INVALID;
    for (size_t previous=0;previous<index;++previous) {
      size_t earlier_bank=previous/(2*length),earlier_local=previous%(2*length);
      const exact_gaussian *earlier=earlier_bank==banks-1 ? out : earlier_bank==0 ? first : second;
      if (exact_alias_invalid(value,component((exact_gaussian *)&earlier[earlier_local/2],earlier_local%2))) return EXACT_INVALID;
    }
  }
  return EXACT_OK;
}
exact_status numerical_radius(const exact_gaussian *value,unsigned precision,unsigned halves) {
  if (!exact_valid(&value->real) || !exact_valid(&value->imaginary) || halves>1
      || value->real.binary_scale>precision || value->imaginary.binary_scale>precision) return EXACT_INVALID;
  exact_dyadic real={0},imaginary={0},real_squared={0},imaginary_squared={0},bound={0};
  exact_status status=EXACT_OK; size_t capacity=(2*(size_t)precision+95)/32;
  TRY(exact_init(&real,capacity)); TRY(exact_init(&imaginary,capacity)); TRY(exact_init(&real_squared,capacity));
  TRY(exact_init(&imaginary_squared,capacity)); TRY(exact_init(&bound,capacity));
  TRY(exact_shift(&real,&value->real,precision)); TRY(exact_shift(&imaginary,&value->imaginary,precision));
  if (real.sign<0) real.sign=1;
  if (imaginary.sign<0) imaginary.sign=1;
  TRY(short_mul_schoolbook(&real_squared,&real,&real)); TRY(short_mul_schoolbook(&imaginary_squared,&imaginary,&imaginary));
  TRY(exact_add(&real_squared,&real_squared,&imaginary_squared)); TRY(exact_set(&bound,1,0)); TRY(exact_shift(&bound,&bound,2*(precision-halves)));
  int order; TRY(exact_compare(&order,&real_squared,&bound)); if (order>0) status=EXACT_INVALID;
done:
  exact_clear(&real); exact_clear(&imaginary); exact_clear(&real_squared); exact_clear(&imaginary_squared); exact_clear(&bound); return status;
}
int numerical_trace_contract(const numerical_trace *trace,const exact_gaussian *first,const exact_gaussian *second,const exact_gaussian *out,size_t length) {
  if (!trace || exact_overlap(trace,sizeof(*trace),first,length*sizeof(*first))
      || exact_overlap(trace,sizeof(*trace),out,length*sizeof(*out))
      || (second && exact_overlap(trace,sizeof(*trace),second,length*sizeof(*second)))) return 0;
  const exact_gaussian *banks[]={first,second,out};
  for (unsigned bank=0;bank<3;++bank) if (banks[bank]) for (size_t index=0;index<length;++index) for (unsigned part=0;part<2;++part) {
    const exact_dyadic *value=component((exact_gaussian *)&banks[bank][index],part);
    if (exact_overlap(trace,sizeof(*trace),value->limbs,value->capacity*sizeof(uint32_t))) return 0;
  }
  return 1;
}
static unsigned logical_to_physical(const synthetic_descriptor *descriptor,unsigned address) {
  unsigned physical=0,offset=0;
  for (unsigned axis=0;axis<descriptor->axes;++axis) {
    for (unsigned bit=0;bit<descriptor->axis_bits[axis];++bit)
      physical|=((address>>(offset+bit))&1)<<descriptor->named_slots[axis][bit];
    offset+=descriptor->axis_bits[axis];
  }
  return physical;
}
exact_status synthetic_prepare(unsigned precision,unsigned ring,const unsigned *lengths,unsigned axes,uint64_t budget,synthetic_plan **out) {
  if (!out || *out || !lengths || precision<2 || precision>256 || ring<2 || ring>8 || (ring&(ring-1)) || !axes || axes>4) return EXACT_INVALID;
  synthetic_descriptor descriptor={0}; descriptor.precision=precision; descriptor.ring_length=ring; descriptor.axes=axes;
  descriptor.records=1; descriptor.numerator_width=precision+2; descriptor.layout_chunk_bits=1;
  for (unsigned axis=0;axis<axes;++axis) {
    if (lengths[axis]!=ring && lengths[axis]!=ring/2) return EXACT_INVALID;
    descriptor.lengths[axis]=lengths[axis]; descriptor.records*=lengths[axis];
    for (unsigned remaining=lengths[axis];remaining>1;remaining>>=1) ++descriptor.axis_bits[axis];
    if (descriptor.axis_bits[axis]>descriptor.rounds) descriptor.rounds=descriptor.axis_bits[axis];
  }
  if (!descriptor.rounds || descriptor.records>64) return EXACT_CAPACITY;
  unsigned slot=0,maximum_axes=0;
  for (unsigned bit=0;bit<descriptor.rounds;++bit) {
    unsigned participating=0;
    for (unsigned axis=0;axis<axes;++axis) if (bit<descriptor.axis_bits[axis]) {
      descriptor.named_slots[axis][bit]=slot++; ++participating;
    }
    if (participating>maximum_axes) maximum_axes=participating;
  }
  synthetic_plan *plan=calloc(1,sizeof(*plan)); if (!plan) return EXACT_ALLOCATION;
  plan->descriptor=descriptor; plan->capacity=(precision+67+31)/32;
  plan->batch_planes=descriptor.records*ring/2; if (plan->batch_planes>880) plan->batch_planes=880;
  plan->batch_length=(64+(size_t)plan->batch_planes)*(1u<<maximum_axes);
  exact_status status=EXACT_OK; size_t length=(size_t)descriptor.records*ring;
  uint64_t required=2*length+2*plan->batch_length+ring; unsigned layer_mask=0;
  for (unsigned bit=0;bit<descriptor.rounds;++bit) {
    unsigned count=0; for (unsigned axis=0;axis<axes;++axis) count+=bit<descriptor.axis_bits[axis];
    if (!(layer_mask&(1u<<count))) { required+=944*(uint64_t)(17+(1u<<count))+1; layer_mask|=1u<<count; }
  }
  if (required>budget) { status=EXACT_CAPACITY; goto done; }
  TRY(numerical_values(&plan->work,length,plan->capacity)); TRY(numerical_values(&plan->next,length,plan->capacity));
  TRY(numerical_values(&plan->batch_input,plan->batch_length,plan->capacity)); TRY(numerical_values(&plan->batch_output,plan->batch_length,plan->capacity));
  TRY(numerical_values(&plan->polynomial,ring,plan->capacity));
  plan->preparation.persistent_limb_bytes=(2*length+2*plan->batch_length+ring)*2*plan->capacity*sizeof(uint32_t);
  plan->preparation.persistent_descriptor_bytes=sizeof(*plan)+(2*length+2*plan->batch_length+ring)*sizeof(exact_gaussian);
  *out=plan; plan=NULL;
done:
  synthetic_clear(plan); return status;
}
void synthetic_clear(synthetic_plan *plan) {
  if (!plan) return;
  for (unsigned axes=1;axes<=4;++axes) phase_layer_clear(plan->layers[axes]);
  size_t length=(size_t)plan->descriptor.records*plan->descriptor.ring_length;
  numerical_clear_values(plan->work,length); numerical_clear_values(plan->next,length);
  numerical_clear_values(plan->batch_input,plan->batch_length); numerical_clear_values(plan->batch_output,plan->batch_length);
  numerical_clear_values(plan->polynomial,plan->descriptor.ring_length); free(plan);
}
exact_status synthetic_describe(const synthetic_plan *plan,synthetic_descriptor *out) {
  if (!plan || !out) return EXACT_INVALID;
  *out=plan->descriptor; return EXACT_OK;
}
exact_status synthetic_warm(synthetic_plan *plan,numerical_trace *out) {
  if (!plan || !out) return EXACT_INVALID;
  for (unsigned bit=0;bit<plan->descriptor.rounds;++bit) {
    unsigned axes=0; for (unsigned axis=0;axis<plan->descriptor.axes;++axis) axes+=bit<plan->descriptor.axis_bits[axis];
    if (!(plan->prepared_mask&(1u<<axes))) {
      exact_status status=phase_layer_prepare(plan->descriptor.precision,axes,65536,&plan->layers[axes]); if (status!=EXACT_OK) return status;
      phase_layer_trace receipt={0}; status=phase_layer_describe(plan->layers[axes],&receipt); if (status!=EXACT_OK) return status;
      plan->prepared_mask|=1u<<axes;
      plan->preparation.prepared_matrix_entries+=receipt.prepared_matrix_entries;
      plan->preparation.persistent_limb_bytes+=receipt.allocated_limb_bytes;
      plan->preparation.persistent_descriptor_bytes+=receipt.allocated_descriptor_bytes;
    }
  }
  *out=plan->preparation; return EXACT_OK;
}
exact_status synthetic_monomial(exact_gaussian *out,const exact_gaussian *input,unsigned ring,int exponent) {
  if (ring<2 || ring>8 || (ring&(ring-1))) return EXACT_INVALID;
  exact_status status=numerical_array_contract(input,NULL,out,ring); if (status!=EXACT_OK) return status;
  int reduced=exponent%(int)(2*ring); if (reduced<0) reduced+=2*ring;
  unsigned shift=(unsigned)reduced%ring; int common=(unsigned)reduced>=ring ? -1 : 1;
  for (unsigned destination=0;destination<ring;++destination) {
    unsigned source=(destination+ring-shift)%ring;
    if (input[source].real.length>out[destination].real.capacity || input[source].imaginary.length>out[destination].imaginary.capacity) return EXACT_CAPACITY;
  }
  for (unsigned destination=0;destination<ring;++destination) {
    unsigned source=(destination+ring-shift)%ring;
    int sign=common*(source+shift>=ring ? -1 : 1);
#ifdef MUTANT_WRAP
    sign=common;
#endif
    status=numerical_copy_value(&out[destination],&input[source]); if (status!=EXACT_OK) return status;
    out[destination].real.sign*=sign; out[destination].imaginary.sign*=sign;
  }
  return EXACT_OK;
}
static unsigned insert_bits(unsigned spectator,unsigned coordinate,const unsigned *selected,unsigned axes,unsigned total_bits) {
  unsigned address=0,cursor=0;
  for (unsigned bit=0;bit<total_bits;++bit) {
    unsigned axis=0; while (axis<axes && selected[axis]!=bit) ++axis;
    address|=((axis<axes ? coordinate>>axis : spectator>>cursor++)&1)<<bit;
  }
  return address;
}
static exact_status twiddles(synthetic_plan *plan,unsigned position,int opposite,numerical_trace *trace) {
  const synthetic_descriptor *descriptor=&plan->descriptor; unsigned ring=descriptor->ring_length;
  for (unsigned address=0;address<descriptor->records;++address) {
    int exponent=0;
    for (unsigned axis=0;axis<descriptor->axes;++axis) if (position<descriptor->axis_bits[axis]) {
      unsigned branch=(address>>descriptor->named_slots[axis][position])&1,index=0;
      for (unsigned bit=0;bit<position;++bit) index|=((address>>descriptor->named_slots[axis][bit])&1)<<bit;
      exponent-=(int)((2*ring/(1u<<(position+1)))*branch*index);
    }
    exact_status status=synthetic_monomial(plan->polynomial,&plan->work[address*ring],ring,opposite ? -exponent : exponent);
    if (status!=EXACT_OK) return status;
    for (unsigned coefficient=0;coefficient<ring;++coefficient) {
      status=numerical_copy_value(&plan->work[address*ring+coefficient],&plan->polynomial[coefficient]); if (status!=EXACT_OK) return status;
    }
    trace->monomial_coefficient_moves+=2*ring;
  }
  return EXACT_OK;
}
static exact_status layer(synthetic_plan *plan,unsigned position,numerical_trace *trace) {
  const synthetic_descriptor *descriptor=&plan->descriptor; unsigned selected[4],axes=0,total_bits=0,ring=descriptor->ring_length;
  for (unsigned axis=0;axis<descriptor->axes;++axis) {
    total_bits+=descriptor->axis_bits[axis];
    if (position<descriptor->axis_bits[axis]) selected[axes++]=descriptor->named_slots[axis][position];
  }
  if (!axes) return EXACT_INVALID;
  if (!plan->layers[axes]) return EXACT_INVALID;
  unsigned slots=1u<<axes,planes=descriptor->records*ring/slots;
  for (unsigned start=0;start<planes;start+=plan->batch_planes) {
    unsigned count=planes-start; if (count>plan->batch_planes) count=plan->batch_planes;
    unsigned rows=64+count; exact_status status=EXACT_OK;
    for (unsigned index=0;index<64*slots;++index) {
      if ((status=exact_set(&plan->batch_input[index].real,0,0)) || (status=exact_set(&plan->batch_input[index].imaginary,0,0))) return status;
    }
    for (unsigned plane=0;plane<count;++plane) for (unsigned coordinate=0;coordinate<slots;++coordinate) {
      unsigned coefficient=(start+plane)%ring,spectator=(start+plane)/ring;
      unsigned address=insert_bits(spectator,coordinate,selected,axes,total_bits);
      status=numerical_copy_value(&plan->batch_input[(64+plane)*slots+coordinate],&plan->work[address*ring+coefficient]); if (status!=EXACT_OK) return status;
    }
    phase_layer_trace receipt={0};
    status=phase_layer_apply(plan->layers[axes],plan->batch_input,rows,plan->batch_output,&receipt); if (status!=EXACT_OK) return status;
    trace->motif_calls+=receipt.frame_calls; ++trace->layer_batches;
    for (unsigned plane=0;plane<count;++plane) for (unsigned coordinate=0;coordinate<slots;++coordinate) {
      unsigned coefficient=(start+plane)%ring,spectator=(start+plane)/ring;
      unsigned address=insert_bits(spectator,coordinate,selected,axes,total_bits);
      status=numerical_copy_value(&plan->next[address*ring+coefficient],&plan->batch_output[(64+plane)*slots+coordinate]); if (status!=EXACT_OK) return status;
    }
  }
  exact_gaussian *temporary=plan->work; plan->work=plan->next; plan->next=temporary;
  ++trace->rounding_sites; return EXACT_OK;
}
exact_status synthetic_transform(synthetic_plan *plan,const exact_gaussian *input,exact_gaussian *out,int opposite,
                                  numerical_trace *trace,numerical_stage_observer observer,void *context) {
  if (!plan || !trace || (opposite!=0 && opposite!=1)) return EXACT_INVALID;
  const synthetic_descriptor *descriptor=&plan->descriptor; size_t length=(size_t)descriptor->records*descriptor->ring_length;
  exact_status status=numerical_array_contract(input,NULL,out,length); if (status!=EXACT_OK) return status;
  if (!numerical_trace_contract(trace,input,NULL,out,length) || exact_overlap(trace,sizeof(*trace),plan,sizeof(*plan))) return EXACT_INVALID;
  for (size_t index=0;index<length;++index) { status=numerical_radius(&input[index],descriptor->precision,0); if (status!=EXACT_OK) return status; }
  numerical_trace receipt={0};
  TRY(synthetic_warm(plan,&receipt)); memset(&receipt,0,sizeof(receipt));
  for (unsigned address=0;address<descriptor->records;++address) for (unsigned coefficient=0;coefficient<descriptor->ring_length;++coefficient) {
    unsigned destination=opposite ? address : logical_to_physical(descriptor,address);
#ifdef MUTANT_LB
    destination=address;
#endif
    TRY(numerical_copy_value(&plan->work[destination*descriptor->ring_length+coefficient],&input[address*descriptor->ring_length+coefficient]));
    ++receipt.layout_coefficient_moves;
  }
  for (unsigned round=0;round<descriptor->rounds;++round) {
    unsigned position=opposite ? round : descriptor->rounds-1-round;
    if (opposite) TRY(twiddles(plan,position,1,&receipt));
    TRY(layer(plan,position,&receipt));
    if (!opposite) TRY(twiddles(plan,position,0,&receipt));
    if (observer) TRY(observer(context,opposite,position,plan->work,length));
  }
  for (unsigned address=0;address<descriptor->records;++address) for (unsigned coefficient=0;coefficient<descriptor->ring_length;++coefficient) {
    unsigned source=opposite ? logical_to_physical(descriptor,address) : address;
    const exact_gaussian *value=&plan->work[source*descriptor->ring_length+coefficient];
    if (value->real.length>out[address*descriptor->ring_length+coefficient].real.capacity || value->imaginary.length>out[address*descriptor->ring_length+coefficient].imaginary.capacity) { status=EXACT_CAPACITY; goto done; }
  }
  for (unsigned address=0;address<descriptor->records;++address) for (unsigned coefficient=0;coefficient<descriptor->ring_length;++coefficient) {
    unsigned source=opposite ? logical_to_physical(descriptor,address) : address;
    TRY(numerical_copy_value(&out[address*descriptor->ring_length+coefficient],&plan->work[source*descriptor->ring_length+coefficient]));
    ++receipt.layout_coefficient_moves;
  }
done:
  receipt.prepared_matrix_entries=plan->preparation.prepared_matrix_entries;
  receipt.persistent_limb_bytes=plan->preparation.persistent_limb_bytes;
  receipt.persistent_descriptor_bytes=plan->preparation.persistent_descriptor_bytes;
  receipt.error_squared_numerator=2*descriptor->rounds*descriptor->rounds; receipt.error_binary_scale=2*descriptor->precision;
  receipt.output_width=descriptor->numerator_width; *trace=receipt; return status;
}
exact_status numerical_published_admission(void) { return EXACT_INVALID; }
