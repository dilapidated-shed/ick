#ifndef NUMERICAL_INTERNAL_H
#define NUMERICAL_INTERNAL_H
#include "numerical.h"
#include "exact_internal.h"
struct synthetic_plan {
  synthetic_descriptor descriptor;
  phase_layer_plan *layers[5];
  exact_gaussian *work,*next,*batch_input,*batch_output,*polynomial;
  size_t capacity,batch_length;
  unsigned batch_planes;
  unsigned prepared_mask;
  numerical_trace preparation;
};
exact_status numerical_values(exact_gaussian **,size_t,size_t);
void numerical_clear_values(exact_gaussian *,size_t);
exact_status numerical_array_contract(const exact_gaussian *,const exact_gaussian *,exact_gaussian *,size_t);
exact_status numerical_radius(const exact_gaussian *,unsigned,unsigned radius_halves);
exact_status numerical_copy_value(exact_gaussian *,const exact_gaussian *);
int numerical_trace_contract(const numerical_trace *,const exact_gaussian *,const exact_gaussian *,const exact_gaussian *,size_t);
#endif
