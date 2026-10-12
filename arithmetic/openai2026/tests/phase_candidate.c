#include "numerical.h"
#include <stdio.h>
#include <stdlib.h>

static int emit(const exact_dyadic *value,unsigned precision) {
  uint8_t bytes[40]; size_t width=(precision+9)/8;
  if (width>sizeof(bytes) || exact_serialize(value,precision,bytes,width)) return 0;
  for (size_t index=0;index<width;++index) printf("%02x",bytes[index]);
  return 1;
}
static int profile(phase_layer_plan *plan,unsigned precision,unsigned axes,unsigned rows,unsigned test) {
  exact_status status=EXACT_OK;
  unsigned slots=1u<<axes; size_t length=(size_t)rows*slots;
  exact_gaussian *input=calloc(length,sizeof(*input)),*output=calloc(length,sizeof(*output)); int success=0;
  if (!input || !output) goto done;
  for (size_t index=0;index<length;++index)
    if (exact_init(&input[index].real,16) || exact_init(&input[index].imaginary,16)
        || exact_init(&output[index].real,16) || exact_init(&output[index].imaginary,16)) goto done;
  for (unsigned row=0;row<rows;++row) for (unsigned coordinate=0;coordinate<slots;++coordinate) {
    if (row>0 && row<64) continue;
    int64_t real=test<slots ? coordinate==test : (int64_t)((row*17+coordinate*7+test)%3)-1;
    int64_t imaginary=test<slots ? 0 : (int64_t)((row*13+coordinate*11+test*3)%3)-1;
    unsigned scale=test<slots ? 0 : test==slots ? 1 : precision;
    if (rows==944) { real=(int64_t)row-400; imaginary=(int64_t)((row*7+coordinate*11)%631)-315; scale=10; }
    if (exact_set(&input[row*slots+coordinate].real,real,scale)
        || exact_set(&input[row*slots+coordinate].imaginary,imaginary,scale)) goto done;
  }
  phase_layer_trace trace;
  status=phase_layer_apply(plan,input,rows,output,&trace);
  if (status!=EXACT_OK) { fprintf(stderr,"phase refusal p=%u D=%u rows=%u test=%u status=%u\n",precision,axes,rows,test,status); goto done; }
  for (unsigned row=0;row<rows;++row) for (unsigned coordinate=0;coordinate<slots;++coordinate) {
    printf("phase\t%u\t%u\t%u\t%u\t%u\t%u\t",precision,axes,rows,test,row,coordinate);
    if (!emit(&output[row*slots+coordinate].real,precision)) goto done;
    putchar('\t'); if (!emit(&output[row*slots+coordinate].imaginary,precision)) goto done;
    putchar('\n');
  }
  fprintf(stderr,"phase-model\tp=%u\tD=%u\trows=%u\treserved_roles=%llu\tpadding_rows=%llu\tframe_calls=%llu\tencoding_additions=%llu\tprepared_matrix_entries=%llu\tallocated_limb_bytes=%llu\tallocated_descriptor_bytes=%llu\tguards=%u,%u\n",
          precision,axes,rows,(unsigned long long)trace.reserved_roles,(unsigned long long)trace.padded_rows,
          (unsigned long long)trace.frame_calls,(unsigned long long)trace.encoding_additions,
          (unsigned long long)trace.prepared_matrix_entries,(unsigned long long)trace.allocated_limb_bytes,
          (unsigned long long)trace.allocated_descriptor_bytes,trace.fractional_guard_bits,trace.magnitude_guard_bits);
  if (fflush(stdout)) goto done;
  success=1;
done:
  if (input) { for (size_t index=0;index<length;++index) { exact_clear(&input[index].real); exact_clear(&input[index].imaginary); } free(input); }
  if (output) { for (size_t index=0;index<length;++index) { exact_clear(&output[index].real); exact_clear(&output[index].imaginary); } free(output); }
  return success;
}
int main(void) {
  for (unsigned axes=1;axes<=4;++axes) {
    phase_layer_plan *plan=NULL;
    if (phase_layer_prepare(9,axes,65536,&plan)) return 39;
    for (unsigned test=0;test<(1u<<axes)+2;++test) if (!profile(plan,9,axes,1,test)) { phase_layer_clear(plan); return 40; }
    phase_layer_clear(plan);
  }
  const unsigned precisions[]={5,33};
  for (unsigned index=0;index<2;++index) {
    phase_layer_plan *plan=NULL;
    if (phase_layer_prepare(precisions[index],2,65536,&plan)) return 39;
    if (!profile(plan,precisions[index],2,129,4+index)) { phase_layer_clear(plan); return 41; }
    if (index==1 && !profile(plan,33,2,944,6)) { phase_layer_clear(plan); return 41; }
    phase_layer_clear(plan);
  }
  return ferror(stdout) ? 42 : 0;
}
