#include "network.h"
#include "exact_internal.h"
#include <stdlib.h>
#include <string.h>

static const unsigned triples[4]={7,11,13,14};
static unsigned data_role(unsigned stage,unsigned invocation,unsigned varying,unsigned bank) {
  unsigned coordinates[3],cursor=0;
  for (unsigned axis=0;axis<3;++axis)
    coordinates[axis]=axis==stage ? varying : cursor++ ? invocation%4 : invocation/4;
  return bank*64+coordinates[0]*16+coordinates[1]*4+coordinates[2];
}
static void rotate(exact_gaussian *value,unsigned phase) {
  for (unsigned turn=0;turn<(phase&3);++turn) {
    exact_dyadic temporary=value->real;
    value->real=value->imaginary; value->imaginary=temporary;
    value->real.sign=-value->real.sign;
  }
}
static void change_frame(exact_gaussian *value,unsigned *current,unsigned next) {
  rotate(value,(next+4-*current)%4); *current=next;
}
exact_status frame_phase_prepare(uint64_t frequency,phase_character_schedule *out,preparation_work *work) {
  if (!out || !work) return EXACT_INVALID;
  phase_character_schedule result={0}; result.frequency=frequency;
  for (unsigned identity=0;identity<944;++identity) {
    frame_role role; frame_matrix matrix;
    exact_status status=frame_role_at(BINARY_LABELS,identity,&role);
    if (status!=EXACT_OK) return status;
    for (unsigned node=0;node<26;++node) {
      unsigned stage=node==0 ? 0 : node==25 ? 2 : (node-1)/8;
      int time=node==0 ? -1 : node==25 ? 8 : (int)((node-1)%8);
      status=frame_projection(BINARY_LABELS,&role,stage,time,&matrix);
      if (status!=EXACT_OK) return status;
      result.phases[node][identity]=(unsigned char)frame_binary_phase(&matrix,frequency);
      work->matrix_entries+=4096;
    }
  }
  *out=result; return EXACT_OK;
}
static exact_status add_value(exact_gaussian *target,const exact_gaussian *control,
                              int sign,int half,exact_dyadic *temporary) {
  for (unsigned channel=0;channel<2;++channel) {
    exact_dyadic *destination=channel ? &target->imaginary : &target->real;
    const exact_dyadic *source=channel ? &control->imaginary : &control->real;
    exact_status status=half ? exact_half(temporary,source) : exact_copy(temporary,source);
    if (status==EXACT_OK) status=sign>0 ? exact_add(destination,destination,temporary)
                                                   : exact_subtract(destination,destination,temporary);
    if (status!=EXACT_OK) return status;
  }
  return EXACT_OK;
}
static exact_status execute(exact_gaussian *values,const phase_character_schedule *schedule,size_t capacity) {
  unsigned phases[944]={0}; exact_dyadic temporary={0};
  exact_status status=exact_init(&temporary,capacity);
  /* Supplied values already have their source frames; no preprocessing occurs. */
  for (unsigned role=0;role<944;++role) phases[role]=schedule->phases[0][role];
  for (unsigned stage=0;stage<3 && status==EXACT_OK;++stage)
    for (unsigned invocation=0;invocation<16 && status==EXACT_OK;++invocation) {
      unsigned scratch=128+(stage*16+invocation)*17;
      for (unsigned time=0;time<8 && status==EXACT_OK;++time) {
        unsigned bank=(time==0 || time==1 || time==4 || time==5), row=stage==1 ? 7-time : time;
        int direction=stage==1 ? -1 : 1;
        for (unsigned triple=0;triple<4 && status==EXACT_OK;++triple) {
          unsigned identity=data_role(stage,invocation,triple,bank);
          change_frame(&values[identity],&phases[identity],schedule->phases[stage*8+time+1][identity]);
        }
        int sides=time==0 || time==2 || time==5 || time==7;
        unsigned first=sides ? 0 : 12, last=sides ? 12 : 17;
        for (unsigned local=first;local<last && status==EXACT_OK;++local) {
          unsigned identity=scratch+local;
          change_frame(&values[identity],&phases[identity],schedule->phases[stage*8+time+1][identity]);
        }
        unsigned source_bank=stage==1 ? 1 : 0,target_bank=1-source_bank;
        if (row==0 || row==2 || row==5 || row==7) {
          unsigned local=0;
          for (unsigned y=0;y<4 && status==EXACT_OK;++y) for (unsigned x=0;x<4 && status==EXACT_OK;++x)
            if (y!=x) {
              exact_gaussian *side=&values[scratch+local++];
              /* In the middle invocation logical Y is physical X, and vice versa. */
              unsigned logical_source=stage==1 ? y : x,logical_target=stage==1 ? x : y;
              if (row==2 || row==7)
                status=add_value(side,&values[data_role(stage,invocation,logical_source,source_bank)],
                                 direction*(row==2 ? 1 : -1),0,&temporary);
              else
                status=add_value(&values[data_role(stage,invocation,logical_target,target_bank)],side,
                                 direction*(row==0 ? 1 : -1),1,&temporary);
            }
        } else if (row==1 || row==4) {
          for (unsigned triple=0;triple<4 && status==EXACT_OK;++triple) {
            exact_gaussian *target=&values[data_role(stage,invocation,triple,target_bank)];
            int sign=direction*(row==1 ? -1 : 1);
            for (unsigned coordinate=0;coordinate<4 && status==EXACT_OK;++coordinate)
              if (triples[triple]&(1u<<coordinate))
                status=add_value(target,&values[scratch+12+coordinate],sign,1,&temporary);
            if (status==EXACT_OK) status=add_value(target,&values[scratch+16],-sign,1,&temporary);
          }
        } else {
          for (unsigned triple=0;triple<4 && status==EXACT_OK;++triple) {
            const exact_gaussian *source=&values[data_role(stage,invocation,triple,source_bank)];
            int sign=direction*(row==3 ? 1 : -1);
            for (unsigned coordinate=0;coordinate<4 && status==EXACT_OK;++coordinate)
              if (triples[triple]&(1u<<coordinate))
                status=add_value(&values[scratch+12+coordinate],source,sign,0,&temporary);
            if (status==EXACT_OK) status=add_value(&values[scratch+16],source,sign,0,&temporary);
          }
        }
      }
    }
  for (unsigned role=0;role<944 && status==EXACT_OK;++role)
    change_frame(&values[role],&phases[role],schedule->phases[25][role]);
  exact_clear(&temporary); return status;
}
exact_status frame_phase_network(exact_gaussian *values,size_t roles,const phase_character_schedule *schedule) {
  if (!values || !schedule || roles!=944) return EXACT_INVALID;
  for (unsigned node=0;node<26;++node) for (unsigned role=0;role<944;++role)
    if (schedule->phases[node][role]>3) return EXACT_INVALID;
  size_t capacity=0;
  for (size_t role=0;role<roles;++role) for (unsigned channel=0;channel<2;++channel) {
    exact_dyadic *value=channel ? &values[role].imaginary : &values[role].real;
    if (!exact_valid(value)) return EXACT_INVALID;
    if (value->capacity>capacity) capacity=value->capacity;
    for (size_t previous=0;previous<2*role+channel;++previous) {
      exact_dyadic *other=previous%2 ? &values[previous/2].imaginary : &values[previous/2].real;
      if (exact_alias_invalid(value,other)) return EXACT_INVALID;
    }
  }
  exact_gaussian *work=calloc(roles,sizeof(*work)); if (!work) return EXACT_ALLOCATION;
  exact_status status=EXACT_OK;
  for (size_t role=0;role<roles && status==EXACT_OK;++role) for (unsigned channel=0;channel<2 && status==EXACT_OK;++channel) {
    exact_dyadic *destination=channel ? &work[role].imaginary : &work[role].real;
    exact_dyadic *source=channel ? &values[role].imaginary : &values[role].real;
    status=exact_init(destination,capacity);
    if (status==EXACT_OK) status=exact_copy(destination,source);
  }
  if (status==EXACT_OK) status=execute(work,schedule,capacity);
  for (size_t role=0;role<roles && status==EXACT_OK;++role)
    if (work[role].real.length>values[role].real.capacity || work[role].imaginary.length>values[role].imaginary.capacity)
      status=EXACT_CAPACITY;
  if (status==EXACT_OK) for (size_t role=0;role<roles;++role) {
    (void)exact_copy(&values[role].real,&work[role].real);
    (void)exact_copy(&values[role].imaginary,&work[role].imaginary);
  }
  for (size_t role=0;role<roles;++role) { exact_clear(&work[role].real); exact_clear(&work[role].imaginary); }
  free(work); return status;
}
