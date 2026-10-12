#include "network.h"
#include <stdlib.h>
#include <string.h>

static const unsigned triples[4]={7,11,13,14};
static unsigned data_role(unsigned stage,unsigned invocation,unsigned varying,unsigned bank) {
  unsigned coordinates[3],cursor=0;
  for (unsigned axis=0;axis<3;++axis)
    coordinates[axis]=axis==stage ? varying : cursor++ ? invocation%4 : invocation/4;
  return bank*64+coordinates[0]*16+coordinates[1]*4+coordinates[2];
}
static exact_status change_frame(unsigned identity,unsigned stage,int time,frame_matrix *previous,
                                  uint64_t point[64],const uint64_t later[64],preparation_work *work) {
  frame_role role; frame_matrix next;
  exact_status status=frame_role_at(RATIONAL_LABELS,identity,&role);
  if (status==EXACT_OK) status=frame_projection(RATIONAL_LABELS,&role,stage,time,&next);
  if (status!=EXACT_OK) return status;
  for (unsigned row=0;row<64;++row) {
    uint64_t difference=0;
    for (unsigned column=0;column<64;++column) {
      int64_t entry=(next.entries[row][column]-previous->entries[row][column])%223;
      if (entry<0) entry+=223;
      difference=(difference+(uint64_t)entry*later[column])%223;
    }
    point[row]=(point[row]+difference*191)%223; /* 216^-1 mod 223 */
  }
  work->matrix_entries+=4096; *previous=next; return EXACT_OK;
}
static int overlaps(const void *left,size_t left_size,const void *right,size_t right_size) {
  uintptr_t a=(uintptr_t)left,b=(uintptr_t)right;
  return a<=b ? b-a<left_size : a-b<right_size;
}
exact_status frame_bit_point_network(uint64_t *values,size_t roles,uint64_t earlier[320][64],
                                     const uint64_t later[64],uint64_t prime,preparation_work *work) {
  if (!values || !earlier || !later || !work || roles!=320 || prime!=223
      || overlaps(values,320*sizeof(uint64_t),earlier,320*64*sizeof(uint64_t))
      || overlaps(values,320*sizeof(uint64_t),later,64*sizeof(uint64_t))
      || overlaps(earlier,320*64*sizeof(uint64_t),later,64*sizeof(uint64_t))
      || overlaps(work,sizeof(*work),values,320*sizeof(uint64_t))
      || overlaps(work,sizeof(*work),earlier,320*64*sizeof(uint64_t))
      || overlaps(work,sizeof(*work),later,64*sizeof(uint64_t))) return EXACT_INVALID;
  for (unsigned coordinate=0;coordinate<64;++coordinate) {
    if (later[coordinate]>=223) return EXACT_INVALID;
    for (unsigned role=0;role<320;++role) if (earlier[role][coordinate]>=223) return EXACT_INVALID;
  }
  frame_matrix *frames=calloc(320,sizeof(*frames));
  uint64_t (*points)[64]=calloc(320,sizeof(*points));
  uint64_t payloads[320]; memcpy(payloads,values,sizeof(payloads));
  if (!frames || !points) { free(frames); free(points); return EXACT_ALLOCATION; }
  memcpy(points,earlier,320*sizeof(*points)); exact_status status=EXACT_OK;
  for (unsigned identity=0;identity<320 && status==EXACT_OK;++identity) {
    frame_role role; status=frame_role_at(RATIONAL_LABELS,identity,&role);
    if (status==EXACT_OK) status=frame_projection(RATIONAL_LABELS,&role,0,-1,&frames[identity]);
    work->matrix_entries+=4096;
  }
  for (unsigned stage=0;stage<3 && status==EXACT_OK;++stage)
    for (unsigned invocation=0;invocation<16 && status==EXACT_OK;++invocation) {
      unsigned scratch=128+(stage*16+invocation)*4;
      for (unsigned time=0;time<8 && status==EXACT_OK;++time) {
        unsigned bank=time==0 || time==1 || time==4 || time==5;
        for (unsigned triple=0;triple<4 && status==EXACT_OK;++triple) {
          unsigned identity=data_role(stage,invocation,triple,bank);
          status=change_frame(identity,stage,(int)time,&frames[identity],points[identity],later,work);
        }
        if (time==0 || time==2 || time==5 || time==7) continue; /* No h=4 bit sides. */
        for (unsigned coordinate=0;coordinate<4 && status==EXACT_OK;++coordinate)
          status=change_frame(scratch+coordinate,stage,(int)time,&frames[scratch+coordinate],points[scratch+coordinate],later,work);
        unsigned representative=data_role(stage,invocation,0,bank);
        for (unsigned triple=0;triple<4 && status==EXACT_OK;++triple)
          if (memcmp(points[representative],points[data_role(stage,invocation,triple,bank)],sizeof(*points))) status=EXACT_INVALID;
        for (unsigned coordinate=0;coordinate<4 && status==EXACT_OK;++coordinate)
          if (memcmp(points[representative],points[scratch+coordinate],sizeof(*points))) status=EXACT_INVALID;
        unsigned row=stage==1 ? 7-time : time;
        for (unsigned triple=0;triple<4 && status==EXACT_OK;++triple)
          for (unsigned coordinate=0;coordinate<4;++coordinate) if (triples[triple]&(1u<<coordinate)) {
            unsigned data=data_role(stage,invocation,triple,bank);
            if (row==1 || row==4) payloads[data]^=payloads[scratch+coordinate];
            else payloads[scratch+coordinate]^=payloads[data];
          }
      }
    }
  for (unsigned role=0;role<320 && status==EXACT_OK;++role)
    status=change_frame(role,2,8,&frames[role],points[role],later,work);
  if (status==EXACT_OK) { memcpy(values,payloads,sizeof(payloads)); memcpy(earlier,points,320*sizeof(*points)); }
  free(frames); free(points); return status;
}
