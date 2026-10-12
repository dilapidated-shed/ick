#include "numerical.h"
#include "exact_internal.h"
#include <stdlib.h>
#include <string.h>

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
struct phase_layer_plan {
  unsigned precision,axes,slots;
  size_t capacity;
  phase_character_schedule schedules[16];
  exact_gaussian *spectra,*roles,*results;
  exact_gaussian temporary;
  phase_layer_trace trace;
};
static exact_dyadic *channel(exact_gaussian *value,unsigned component) { return component ? &value->imaginary : &value->real; }
static const exact_dyadic *const_channel(const exact_gaussian *value,unsigned component) { return component ? &value->imaginary : &value->real; }
static void rotate(exact_gaussian *value,unsigned phase) {
  for (unsigned turn=0;turn<(phase&3);++turn) {
    exact_dyadic temporary=value->real; value->real=value->imaginary; value->imaginary=temporary; value->real.sign=-value->real.sign;
  }
}
static uint64_t embed(unsigned coordinate) {
  uint64_t vector=0;
  for (unsigned first=0;first<4;++first) if ((coordinate>>first)&1)
    for (unsigned second=0;second<3;++second) for (unsigned third=0;third<3;++third)
      vector|=UINT64_C(1)<<(16*first+4*second+third);
  return vector;
}
static exact_status initialize_values(exact_gaussian **out,size_t length,size_t capacity) {
  exact_gaussian *values=calloc(length,sizeof(*values)); if (!values) return EXACT_ALLOCATION;
  *out=values;
  for (size_t index=0;index<length;++index) for (unsigned component=0;component<2;++component) {
    exact_status status=exact_init(channel(&values[index],component),capacity); if (status!=EXACT_OK) return status;
  }
  return EXACT_OK;
}
static void clear_values(exact_gaussian *values,size_t length) {
  if (!values) return;
  for (size_t index=0;index<length;++index) { exact_clear(&values[index].real); exact_clear(&values[index].imaginary); }
  free(values);
}
exact_status phase_layer_prepare(unsigned precision,unsigned axes,uint64_t budget,phase_layer_plan **out) {
  if (!out || *out || precision<2 || precision>256 || !axes || axes>4) return EXACT_INVALID;
  unsigned slots=1u<<axes;
  if (budget<944*(uint64_t)(16+1+slots)+1) return EXACT_CAPACITY;
  phase_layer_plan *plan=calloc(1,sizeof(*plan)); if (!plan) return EXACT_ALLOCATION;
  plan->precision=precision; plan->axes=axes; plan->slots=1u<<axes;
  plan->capacity=(precision+67+31)/32;
  plan->trace.reserved_roles=944; plan->trace.fractional_guard_bits=32; plan->trace.magnitude_guard_bits=32;
  exact_status status=EXACT_OK; preparation_work work={0};
  frame_role primary; TRY(frame_role_at(BINARY_LABELS,0,&primary));
  if (embed(7)!=frame_tensor_indicator(primary.coordinates)) { status=EXACT_INVALID; goto done; }
  for (unsigned axis=0;axis<4;++axis) {
    if (frame_popcount(embed(1u<<axis))!=9) { status=EXACT_INVALID; goto done; }
    for (unsigned earlier=0;earlier<axis;++earlier)
      if (embed(1u<<axis)&embed(1u<<earlier)) { status=EXACT_INVALID; goto done; }
  }
  for (unsigned frequency=0;frequency<16;++frequency) TRY(frame_phase_prepare(embed(frequency),&plan->schedules[frequency],&work));
  TRY(initialize_values(&plan->spectra,944*16,plan->capacity));
  TRY(initialize_values(&plan->roles,944,plan->capacity));
  TRY(initialize_values(&plan->results,944*plan->slots,plan->capacity));
  TRY(exact_init(&plan->temporary.real,plan->capacity)); TRY(exact_init(&plan->temporary.imaginary,plan->capacity));
  plan->trace.prepared_matrix_entries=work.matrix_entries;
  plan->trace.allocated_limb_bytes=(uint64_t)(944*16+944+944*plan->slots+1)*2*plan->capacity*sizeof(uint32_t);
  plan->trace.allocated_descriptor_bytes=sizeof(*plan)+(944*16+944+944*plan->slots)*sizeof(exact_gaussian);
  *out=plan; plan=NULL;
done:
  phase_layer_clear(plan); return status;
}
void phase_layer_clear(phase_layer_plan *plan) {
  if (!plan) return;
  clear_values(plan->spectra,944*16); clear_values(plan->roles,944); clear_values(plan->results,944*plan->slots);
  exact_clear(&plan->temporary.real); exact_clear(&plan->temporary.imaginary); free(plan);
}
static exact_status disk_value(const exact_gaussian *value,unsigned precision) {
  if (!exact_valid(&value->real) || !exact_valid(&value->imaginary)
      || value->real.binary_scale>precision || value->imaginary.binary_scale>precision) return EXACT_INVALID;
  size_t capacity=(2*(size_t)precision+95)/32;
  exact_dyadic real={0},imaginary={0},real_square={0},imaginary_square={0},one={0}; exact_status status=EXACT_OK;
  TRY(exact_init(&real,capacity)); TRY(exact_init(&imaginary,capacity)); TRY(exact_init(&real_square,capacity));
  TRY(exact_init(&imaginary_square,capacity)); TRY(exact_init(&one,capacity));
  TRY(exact_shift(&real,&value->real,precision)); TRY(exact_shift(&imaginary,&value->imaginary,precision));
  if (real.sign<0) real.sign=1;
  if (imaginary.sign<0) imaginary.sign=1;
  TRY(short_mul_schoolbook(&real_square,&real,&real)); TRY(short_mul_schoolbook(&imaginary_square,&imaginary,&imaginary));
  TRY(exact_add(&real_square,&real_square,&imaginary_square)); TRY(exact_set(&one,1,0)); TRY(exact_shift(&one,&one,2*precision));
  int comparison; TRY(exact_compare(&comparison,&real_square,&one)); if (comparison>0) status=EXACT_INVALID;
done:
  exact_clear(&real); exact_clear(&imaginary); exact_clear(&real_square); exact_clear(&imaginary_square); exact_clear(&one); return status;
}
static exact_status add_value(exact_gaussian *out,const exact_gaussian *in,int sign) {
  exact_status status=sign>0 ? exact_add(&out->real,&out->real,&in->real) : exact_subtract(&out->real,&out->real,&in->real);
  if (status==EXACT_OK) status=sign>0 ? exact_add(&out->imaginary,&out->imaginary,&in->imaginary) : exact_subtract(&out->imaginary,&out->imaginary,&in->imaginary);
  return status;
}
static exact_status multiply_b(phase_layer_plan *plan,exact_gaussian *value) {
  exact_status status=exact_add(&plan->temporary.real,&value->real,&value->imaginary);
  if (status==EXACT_OK) status=exact_subtract(&plan->temporary.imaginary,&value->imaginary,&value->real);
  if (status==EXACT_OK) status=exact_half(&value->real,&plan->temporary.real);
  if (status==EXACT_OK) status=exact_half(&value->imaginary,&plan->temporary.imaginary);
  return status;
}
exact_status phase_layer_apply(phase_layer_plan *plan,const exact_gaussian *input,unsigned rows,
                                 exact_gaussian *out,phase_layer_trace *trace) {
  if (!plan || !input || !out || !trace || !rows || rows>944) return EXACT_INVALID;
  size_t length=(size_t)rows*plan->slots;
  if (exact_overlap(input,length*sizeof(*input),out,length*sizeof(*out))
      || exact_overlap(trace,sizeof(*trace),input,length*sizeof(*input)) || exact_overlap(trace,sizeof(*trace),out,length*sizeof(*out))) return EXACT_INVALID;
  for (size_t index=0;index<4*length;++index) {
    const exact_dyadic *value=index<2*length ? const_channel(&input[index/2],index%2) : const_channel(&out[(index-2*length)/2],index%2);
    if (!exact_valid(value) || exact_overlap(trace,sizeof(*trace),value->limbs,value->capacity*sizeof(uint32_t))) return EXACT_INVALID;
    for (size_t previous=0;previous<index;++previous) {
      const exact_dyadic *other=previous<2*length ? const_channel(&input[previous/2],previous%2) : const_channel(&out[(previous-2*length)/2],previous%2);
      if (exact_alias_invalid(value,other)) return EXACT_INVALID;
    }
  }
  for (unsigned row=0;row<rows;++row) for (unsigned coordinate=0;coordinate<plan->slots;++coordinate) {
    const exact_gaussian *value=&input[row*plan->slots+coordinate];
    if (row>0 && row<64 && (value->real.length || value->imaginary.length)) return EXACT_INVALID;
    exact_status status=disk_value(value,plan->precision); if (status!=EXACT_OK) return status;
  }
  exact_status status=EXACT_OK; plan->trace.frame_calls=0; plan->trace.encoding_additions=0; plan->trace.padded_rows=944-rows;
  for (size_t index=0;index<944*16;++index) { TRY(exact_set(&plan->spectra[index].real,0,0)); TRY(exact_set(&plan->spectra[index].imaginary,0,0)); }
  /* Direct finite character encoding; this is a representation conversion.
   * The requested H0 operator is executed by the accepted framed motif below. */
  for (unsigned row=0;row<rows;++row) for (unsigned frequency=0;frequency<16;++frequency) {
    exact_gaussian *coefficient=&plan->spectra[row*16+frequency];
    for (unsigned coordinate=0;coordinate<16;++coordinate) {
      const exact_gaussian *value=&input[row*plan->slots+(coordinate&(plan->slots-1))];
      TRY(exact_copy(&plan->temporary.real,&value->real)); TRY(exact_copy(&plan->temporary.imaginary,&value->imaginary));
      rotate(&plan->temporary,frame_popcount(coordinate&(plan->slots-1)));
      TRY(add_value(coefficient,&plan->temporary,frame_popcount(frequency&coordinate)&1 ? -1 : 1)); ++plan->trace.encoding_additions;
    }
    for (unsigned half=0;half<4;++half) { TRY(exact_half(&coefficient->real,&coefficient->real)); TRY(exact_half(&coefficient->imaginary,&coefficient->imaginary)); }
#ifdef MUTANT_EARLY_ROUND
    TRY(exact_truncate(&coefficient->real,&coefficient->real,plan->precision)); TRY(exact_truncate(&coefficient->imaginary,&coefficient->imaginary,plan->precision));
#endif
  }
  for (unsigned frequency=0;frequency<16;++frequency) {
    for (unsigned row=0;row<944;++row) {
      unsigned source_frequency=row==0 ? frequency^7 : frequency;
      const exact_gaussian *coefficient=&plan->spectra[row*16+source_frequency];
      TRY(exact_copy(&plan->roles[row].real,&coefficient->real)); TRY(exact_copy(&plan->roles[row].imaginary,&coefficient->imaginary));
    }
    TRY(frame_phase_network(plan->roles,944,&plan->schedules[frequency])); ++plan->trace.frame_calls;
    for (unsigned row=0;row<944;++row) {
      unsigned physical=frame_route_target(row),destination_frequency=row==0 ? frequency^7 : frequency;
      exact_gaussian *coefficient=&plan->roles[physical];
      if (row>=64 && row<128) rotate(coefficient,2);
      if (row==0) rotate(coefficient,27);
      /* For every role this writes exactly its already-consumed source
       * frequency, so the next frequency still has its original input. */
      TRY(exact_copy(&plan->spectra[row*16+destination_frequency].real,&coefficient->real));
      TRY(exact_copy(&plan->spectra[row*16+destination_frequency].imaginary,&coefficient->imaginary));
    }
  }
  for (unsigned row=0;row<944;++row) for (unsigned coordinate=0;coordinate<plan->slots;++coordinate) {
    exact_gaussian *value=&plan->results[row*plan->slots+coordinate];
    TRY(exact_set(&value->real,0,0)); TRY(exact_set(&value->imaginary,0,0));
    for (unsigned frequency=0;frequency<16;++frequency)
      TRY(add_value(value,&plan->spectra[row*16+frequency],frame_popcount(frequency&coordinate)&1 ? -1 : 1));
    rotate(value,frame_popcount(coordinate));
    for (unsigned factor=0;factor<plan->axes;++factor) TRY(multiply_b(plan,value));
    TRY(exact_truncate(&value->real,&value->real,plan->precision)); TRY(exact_truncate(&value->imaginary,&value->imaginary,plan->precision));
    TRY(disk_value(value,plan->precision));
    if (row>=rows && (value->real.length || value->imaginary.length)) { status=EXACT_INVALID; goto done; }
    if (row<rows && (value->real.length>out[row*plan->slots+coordinate].real.capacity
                    || value->imaginary.length>out[row*plan->slots+coordinate].imaginary.capacity)) { status=EXACT_CAPACITY; goto done; }
  }
  for (size_t index=0;index<length;++index) {
    TRY(exact_copy(&out[index].real,&plan->results[index].real)); TRY(exact_copy(&out[index].imaginary,&plan->results[index].imaginary));
  }
done:
  *trace=plan->trace; return status;
}
