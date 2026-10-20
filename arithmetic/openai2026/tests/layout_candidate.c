#include "layout.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int stream_checks(void) {
  uint64_t input[36],output[60]; role_stream streams[3]={{0}}; stream_work work={0};
  for (unsigned index=0;index<36;++index) input[index]=index+1000;
  size_t order[]={2,0,1};
  if (stream_split_rows(input,36,2,6,3,3,streams,&work)
      || stream_merge_rows(streams,3,order,2,6,3,output,36,&work)) { stream_clear(streams,3); return 0; }
  for (size_t prefix=0;prefix<2;++prefix) for (size_t row=0;row<6;++row) for (size_t tail=0;tail<3;++tail)
    if (output[(prefix*6+row)*3+tail]!=input[(prefix*6+(row/3)*3+order[row%3])*3+tail]) {
      stream_clear(streams,3); return 0;
    }
  stream_clear(streams,3);
  if (stream_pad_width(input,2,6,3,10,output,60,&work)) return 0;
  for (size_t prefix=0;prefix<2;++prefix) for (size_t row=0;row<10;++row) for (size_t tail=0;tail<3;++tail)
    if (output[(prefix*10+row)*3+tail]!=(row<6 ? input[(prefix*6+row)*3+tail] : 0)) return 0;
  uint64_t earlier[]={0,6,2},later[]={5,1,3},saved_earlier[3],saved_later[3];
  memcpy(saved_earlier,earlier,sizeof(earlier)); memcpy(saved_later,later,sizeof(later));
  if (layout_interchange(earlier,later,3,7,&work)
      || memcmp(earlier,saved_later,sizeof(earlier)) || memcmp(later,saved_earlier,sizeof(later))) return 0;
  uint64_t alias[]={1,2,3,4};
  if (layout_interchange(alias,alias+1,3,7,&work)!=EXACT_INVALID || alias[0]!=1 || alias[1]!=2) return 0;
  fprintf(stderr,"streams\ttape_moves=%llu\tcounter_moves=%llu\tram_operations=%llu\trecords=%llu\n",
          (unsigned long long)work.tape_moves,(unsigned long long)work.counter_moves,
          (unsigned long long)work.ram_operations,(unsigned long long)work.records);
  return 1;
}
static uint64_t address_rank(packed_address address, unsigned width) {
  return ((address.control<<width)|address.target)<<width|address.scratch;
}
static packed_address from_rank(uint64_t rank, unsigned width) {
  uint64_t mask=(UINT64_C(1)<<width)-1;
  return (packed_address){rank>>(2*width),(rank>>width)&mask,rank&mask};
}
static int correction_orbit(void) {
  packed_layout layout={6,3,0}; packed_address origin={65,63,63},start=origin;
  if (packed_rotations(layout,&start,0)) return 0;
  int changed=start.target!=origin.target || start.scratch!=origin.scratch;
  if (!changed) return 0;
  exceptional_record records[65536]; uint64_t holes[65536],payloads[65536]; size_t count=0;
  packed_address current=start;
  do {
    if (count==65536) { fprintf(stderr,"correction orbit exceeds 65536-record budget\n"); return 0; }
    packed_address next=current; if (packed_correct(layout,&next)) return 0;
    records[count]=(exceptional_record){address_rank(current,18),address_rank(next,18),count+100};
    holes[count]=records[count].rank; ++count; current=next;
  } while (address_rank(current,18)!=address_rank(start,18));
  for (size_t index=1;index<count;++index) {
    uint64_t value=holes[index]; size_t position=index;
    while (position && holes[position-1]>value) { holes[position]=holes[position-1]; --position; }
    holes[position]=value;
  }
  uint64_t expected[65536];
  for (size_t hole=0;hole<count;++hole) {
    int found=0;
    for (size_t record=0;record<count;++record) if (records[record].destination==holes[hole]) {
      expected[hole]=records[record].payload; found=1;
    }
    if (!found) return 0;
    packed_address decoded=from_rank(holes[hole],18); int bad=0;
    if (packed_bad(layout,&decoded,&bad) || !bad) return 0;
  }
  stream_work work={0};
  if (packed_sort_reinsert(records,count,holes,count,payloads,&work)
      || memcmp(expected,payloads,count*sizeof(uint64_t))) return 0;
  fprintf(stderr,"exceptional-orbit\trecords=%zu\ttape_moves=%llu\n",count,(unsigned long long)work.tape_moves);
  return 1;
}
int main(void) {
  if (!stream_checks()) { fprintf(stderr,"stream check failed\n"); return 40; }
  if (!correction_orbit()) { fprintf(stderr,"correction orbit check failed\n"); return 40; }
  const unsigned guards[]={6,7};
  const uint64_t boundaries[]={0,1,2,19,20,21,22,31,32,41,42,43,62,63,64,65,126,127,128,129};
  uint64_t correction_count=0;
  for (unsigned guard_index=0;guard_index<2;++guard_index) for (unsigned count=1;count<=4;++count)
    for (unsigned position=0;position<2;++position) {
      packed_layout layout={guards[guard_index],count,position ? guards[guard_index]-1 : 0}; unsigned width;
      if (packed_admit(layout,&width)) return 41;
      uint64_t maximum=(UINT64_C(1)<<width)-1;
      for (unsigned control_index=0;control_index<16;++control_index) {
        uint64_t control=0;
        for (unsigned bit=0;bit<count;++bit) if ((control_index>>bit)&1)
          control|=UINT64_C(1)<<(layout.first_bit+bit*layout.guard_width);
        for (unsigned y_index=0;y_index<22;++y_index) for (unsigned z_index=0;z_index<22;++z_index) {
          uint64_t y=y_index<20 ? boundaries[y_index]&maximum : maximum-(21-y_index);
          uint64_t z=z_index<20 ? boundaries[z_index]&maximum : maximum-(21-z_index);
          packed_address original={control,y,z},actual=original,inverted;
          if (packed_rotations(layout,&actual,0)) return 42;
          inverted=actual;
          if (packed_rotations(layout,&inverted,1) || memcmp(&inverted,&original,sizeof(original))) return 43;
          int original_bad=0,current_bad=0;
          if (packed_bad(layout,&original,&original_bad) || packed_bad(layout,&actual,&current_bad)
              || original_bad!=current_bad) return 44;
          correction_count+=actual.target!=original.target || actual.scratch!=original.scratch;
          if (packed_correct(layout,&actual)) return 45;
          /* The highest selected bit is the final elementary two-bit XOR. */
          unsigned highest_bit=layout.first_bit+(count-1)*layout.guard_width;
          actual.target^=actual.control&(UINT64_C(1)<<highest_bit);
          printf("packed\t%u\t%u\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\n",layout.guard_width,count,layout.first_bit,
                 (unsigned long long)control,(unsigned long long)y,(unsigned long long)z,
                 (unsigned long long)actual.target,(unsigned long long)actual.scratch);
        }
      }
    }
  fprintf(stderr,"packed\tobserved-rotation-changes=%llu\n",(unsigned long long)correction_count);
  return ferror(stdout) ? 46 : 0;
}
