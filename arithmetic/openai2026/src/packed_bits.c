#include "layout.h"
#include <stdlib.h>
#include <string.h>

exact_status packed_admit(packed_layout layout, unsigned *width) {
  if (!width || layout.guard_width<6 || !layout.selected_count || layout.first_bit>=layout.guard_width)
    return EXACT_INVALID;
  if (layout.guard_width>30 || layout.selected_count>30/layout.guard_width) return EXACT_CAPACITY;
  *width=layout.guard_width*layout.selected_count; return EXACT_OK;
}
static exact_status valid_address(packed_layout layout, const packed_address *address, unsigned *width) {
  if (!address) return EXACT_INVALID;
  exact_status status=packed_admit(layout,width); if (status!=EXACT_OK) return status;
  uint64_t bound=UINT64_C(1)<<*width;
  return address->control<bound && address->target<bound && address->scratch<bound ? EXACT_OK : EXACT_INVALID;
}
exact_status packed_rotations(packed_layout layout, packed_address *address, int inverse) {
  unsigned width; exact_status status=valid_address(layout,address,&width);
  if (status!=EXACT_OK || (inverse!=0 && inverse!=1)) return status!=EXACT_OK ? status : EXACT_INVALID;
  packed_address result=*address; uint64_t mask=(UINT64_C(1)<<width)-1;
  const unsigned target_is_y[]={1,0,1,0,0,1,0,1};
  const unsigned tested_parity[]={0,0,0,0,1,1,1,1};
  const int signs[]={-1,-1,1,1,1,1,-1,-1};
  for (unsigned position=0;position<8;++position) {
    unsigned step=inverse ? 7-position : position;
#ifdef MUTANT_INVERSE_ORDER
    if (inverse) step=position;
#endif
    uint64_t control_chunk=target_is_y[step] ? result.scratch : result.target, offset=0;
    for (unsigned index=0;index+1<layout.selected_count;++index) {
      unsigned bit=layout.first_bit+index*layout.guard_width;
      if (((result.control>>bit)&1) && ((control_chunk>>bit)&1)==tested_parity[step]) offset|=UINT64_C(1)<<bit;
    }
    int sign=signs[step]*(inverse ? -1 : 1);
    uint64_t *target=target_is_y[step] ? &result.target : &result.scratch;
    *target=(sign>0 ? *target+offset : *target-offset)&mask;
  }
  *address=result; return EXACT_OK;
}
exact_status packed_ideal(packed_layout layout, packed_address *address, int include_highest) {
  unsigned width; exact_status status=valid_address(layout,address,&width); if (status!=EXACT_OK) return status;
  unsigned count=include_highest ? layout.selected_count : layout.selected_count-1;
  packed_address result=*address;
  for (unsigned index=0;index<count;++index) {
    unsigned bit=layout.first_bit+index*layout.guard_width;
    result.target^=result.control&(UINT64_C(1)<<bit);
  }
  *address=result; return EXACT_OK;
}
exact_status packed_bad(packed_layout layout, const packed_address *address, int *bad) {
  unsigned width; exact_status status=valid_address(layout,address,&width);
  if (status!=EXACT_OK || !bad) return status!=EXACT_OK ? status : EXACT_INVALID;
  uint64_t guard_mask=(UINT64_C(1)<<(layout.guard_width-1))-1; int result=0;
  for (unsigned index=0;index+1<layout.selected_count;++index) {
    unsigned shift=layout.first_bit+index*layout.guard_width+1;
    uint64_t y=(address->target>>shift)&guard_mask, z=(address->scratch>>shift)&guard_mask;
    result|=y<10 || y>guard_mask-10 || z<10 || z>guard_mask-10;
  }
  *bad=result; return EXACT_OK;
}
exact_status packed_correct(packed_layout layout, packed_address *address) {
#ifdef MUTANT_OMITTED_CORRECTION
  unsigned width; return valid_address(layout,address,&width);
#endif
  int bad=0; exact_status status=packed_bad(layout,address,&bad); if (status!=EXACT_OK || !bad) return status;
  packed_address result=*address;
  if ((status=packed_rotations(layout,&result,1))!=EXACT_OK
      || (status=packed_ideal(layout,&result,0))!=EXACT_OK) return status;
  *address=result; return EXACT_OK;
}
exact_status packed_sort_reinsert(exceptional_record *records, size_t length,
                                  uint64_t *holes, size_t hole_count,
                                  uint64_t *payloads, stream_work *work) {
  if (!records || !holes || !payloads || !work || length!=hole_count) return EXACT_INVALID;
  if (length>SIZE_MAX/sizeof(*records)) return EXACT_CAPACITY;
  exceptional_record *ordered=calloc(length,sizeof(*ordered));
  exceptional_record *zeros=calloc(length,sizeof(*zeros)), *ones=calloc(length,sizeof(*ones));
  if (length && (!ordered || !zeros || !ones)) { free(ordered); free(zeros); free(ones); return EXACT_ALLOCATION; }
  memcpy(ordered,records,length*sizeof(*records));
  /* Two sequential bucket tapes, then one sequential merge. Each pass includes
   * rewinds; this is not a random-write partition charged as a tape scan. */
  for (unsigned bit=0;bit<64;++bit) {
    size_t zero=0,one=0;
    for (size_t index=0;index<length;++index)
      if ((ordered[index].destination>>bit)&1) ones[one++]=ordered[index]; else zeros[zero++]=ordered[index];
    for (size_t index=0;index<zero;++index) ordered[index]=zeros[index];
    for (size_t index=0;index<one;++index) ordered[zero+index]=ones[index];
    work->tape_moves+=8*length;
  }
  free(zeros); free(ones);
  for (size_t index=0;index<length;++index)
    if (ordered[index].destination!=holes[index] || (index && holes[index]<=holes[index-1])) { free(ordered); return EXACT_INVALID; }
  memcpy(records,ordered,length*sizeof(*records));
  for (size_t index=0;index<length;++index) { payloads[index]=ordered[index].payload; work->tape_moves+=2; }
  free(ordered);
  return EXACT_OK;
}
