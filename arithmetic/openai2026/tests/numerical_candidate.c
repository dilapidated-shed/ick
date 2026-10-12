#include "numerical.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

static int initialize(exact_gaussian **out,size_t length) {
  *out=calloc(length,sizeof(**out)); if (!*out) return 0;
  for (size_t index=0;index<length;++index)
    if (exact_init(&(*out)[index].real,32) || exact_init(&(*out)[index].imaginary,32)) return 0;
  return 1;
}
static void clear(exact_gaussian *values,size_t length) {
  if (!values) return;
  for (size_t index=0;index<length;++index) { exact_clear(&values[index].real); exact_clear(&values[index].imaginary); }
  free(values);
}
static int bytes(const exact_dyadic *value,unsigned precision) {
  unsigned char buffer[40]; size_t width=(precision+9)/8;
  if (width>sizeof(buffer) || exact_serialize(value,precision,buffer,width)) return 0;
  for (size_t index=0;index<width;++index) printf("%02x",buffer[index]);
  return 1;
}
static int values(const char *tag,unsigned precision,unsigned profile,unsigned test,unsigned stage,const exact_gaussian *input,size_t length) {
  for (size_t index=0;index<length;++index) {
    printf("%s\t%u\t%u\t%u\t%u\t%zu\t",tag,precision,profile,test,stage,index);
    if (!bytes(&input[index].real,precision)) return 0;
    putchar('\t'); if (!bytes(&input[index].imaginary,precision)) return 0;
    putchar('\n');
  }
  return !ferror(stdout);
}
static int children(void) {
  exact_gaussian *input=NULL,*forward=NULL,*inverse=NULL,*restored=NULL; int success=0;
  if (!initialize(&input,2) || !initialize(&forward,2) || !initialize(&inverse,2) || !initialize(&restored,2)) goto done;
  const unsigned precisions[]={9,33,101};
  for (unsigned which=0;which<3;++which) for (unsigned test=0;test<12;++test) {
    unsigned p=precisions[which];
    for (unsigned index=0;index<2;++index)
      if (exact_set(&input[index].real,(int64_t)((test*7+index*3)%5)-2,p)
          || exact_set(&input[index].imaginary,(int64_t)((test*11+index*7)%7)-3,p)) goto done;
    if (numerical_C_child(forward,input,0) || numerical_C_child(inverse,input,1)
        || numerical_C_child(restored,forward,1)) goto done;
    if (!values("child-forward",p+2,which,test,0,forward,2)
        || !values("child-inverse",p+2,which,test,0,inverse,2)
        || !values("child-restored",p+2,which,test,0,restored,2)) goto done;
  }
  success=1;
done:
  clear(input,2); clear(forward,2); clear(inverse,2); clear(restored,2); return success;
}
static int monomials(void) {
  exact_gaussian *input=NULL,*output=NULL; int success=0;
  if (!initialize(&input,8) || !initialize(&output,8)) goto done;
  for (unsigned ring=2;ring<=8;ring*=2) for (int exponent=-17;exponent<=17;++exponent) {
    for (unsigned index=0;index<ring;++index)
      if (exact_set(&input[index].real,(int64_t)index-3,9) || exact_set(&input[index].imaginary,2*(int64_t)index-5,9)) goto done;
    if (synthetic_monomial(output,input,ring,exponent)
        || !values("monomial",9,ring,(unsigned)(exponent+17),0,output,ring)) goto done;
  }
  success=1;
done:
  clear(input,8); clear(output,8); return success;
}
typedef struct { unsigned precision,profile,test; } observation;
static exact_status round_value(void *context,int opposite,unsigned round,const exact_gaussian *input,size_t length) {
  observation *description=context;
  return values(opposite ? "op-round" : "tf-round",description->precision,description->profile,description->test,round,input,length) ? EXACT_OK : EXACT_INVALID;
}
static exact_status convolution_value(void *context,const char *stage,unsigned record,const exact_gaussian *input,size_t length,const short_mul_trace *receipt) {
  observation *description=context;
  if (!values(stage,description->precision,description->profile,description->test,record,input,length)) return EXACT_INVALID;
  if (receipt) {
    if (strcmp(receipt->identity,"reduced-schoolbook") || receipt->calls!=4) return EXACT_INVALID;
    for (unsigned product=0;product<4;++product)
      printf("short\t%u\t%u\t%u\t%u\t%u\t%zu\t%zu\t%zu\t%llu\t%s\n",description->precision,description->profile,description->test,record,product,
        receipt->left_bits[product],receipt->right_bits[product],receipt->result_bits[product],(unsigned long long)receipt->validation_products,receipt->identity);
  }
  return ferror(stdout) ? EXACT_INVALID : EXACT_OK;
}
static int fill(exact_gaussian *input,size_t length,unsigned p,unsigned test,int convolution,int second) {
  for (size_t index=0;index<length;++index) {
    int64_t real,imaginary; unsigned scale;
    if (!convolution && test<2*length) {
      real=test<length && index==test; imaginary=test>=length && index==test-length; scale=0;
    } else {
      real=(int64_t)((index*7+test*11+second*3)%3)-1;
      imaginary=(int64_t)((index*11+test*3+second*7)%3)-1;
      scale=convolution ? 2 : test==2*length ? 1 : p;
    }
    if (exact_set(&input[index].real,real,scale) || exact_set(&input[index].imaginary,imaginary,scale)) return 0;
  }
  return 1;
}
static void trace_value(const char *kind,const observation *description,const numerical_trace *trace,double seconds) {
  struct rusage usage; long rss=getrusage(RUSAGE_SELF,&usage) ? -1 : usage.ru_maxrss;
  fprintf(stderr,"%s\tp=%u\tprofile=%u\ttest=%u\tmotif_calls=%llu\tbatches=%llu\tlayout_moves=%llu\tmonomial_moves=%llu\trounds=%llu\tshort_calls=%llu\tprepared_matrix_entries=%llu\tpersistent_limb_bytes=%llu\tpersistent_descriptor_bytes=%llu\terror_squared=%u*2^-%u\toutput_width=%u\tcpu_seconds=%.9f\trss_linux_kib=%ld\n",kind,description->precision,description->profile,description->test,
    (unsigned long long)trace->motif_calls,(unsigned long long)trace->layer_batches,(unsigned long long)trace->layout_coefficient_moves,
    (unsigned long long)trace->monomial_coefficient_moves,(unsigned long long)trace->rounding_sites,(unsigned long long)trace->short_calls,
    (unsigned long long)trace->prepared_matrix_entries,(unsigned long long)trace->persistent_limb_bytes,(unsigned long long)trace->persistent_descriptor_bytes,
    trace->error_squared_numerator,trace->error_binary_scale,trace->output_width,seconds,rss);
}
static int profile(unsigned p,unsigned ring,const unsigned *axes,unsigned dimension,unsigned identifier,int convolution) {
  synthetic_plan *plan=NULL; exact_gaussian *input=NULL,*second=NULL,*output=NULL,*opposite=NULL; int success=0;
  synthetic_descriptor descriptor; numerical_trace trace={0}; observation description={p,identifier,0};
  clock_t beginning=clock();
  if (synthetic_prepare(p,ring,axes,dimension,65536,&plan) || synthetic_describe(plan,&descriptor) || synthetic_warm(plan,&trace)) goto done;
  trace_value("preparation",&description,&trace,(double)(clock()-beginning)/CLOCKS_PER_SEC);
  size_t length=(size_t)descriptor.records*ring;
  if (!initialize(&input,length) || !initialize(&second,length) || !initialize(&output,length) || !initialize(&opposite,length)) goto done;
  unsigned tests=convolution ? 3 : identifier<2 ? 2*(unsigned)length+2 : 2;
  for (unsigned ordinal=0;ordinal<tests;++ordinal) {
    unsigned test=convolution || identifier<2 ? ordinal : 2*(unsigned)length+ordinal; description.test=test;
    if (!fill(input,length,p,test,convolution,0) || !fill(second,length,p,test,convolution,1)) goto done;
    beginning=clock();
    if (convolution) {
      const short_mul_provider provider={"reduced-schoolbook",short_mul_schoolbook};
      if (numerical_convolution_observed(plan,input,second,output,&provider,&trace,convolution_value,&description)
          || !values("convolution",p,identifier,test,0,output,length)) goto done;
      trace_value("convolution",&description,&trace,(double)(clock()-beginning)/CLOCKS_PER_SEC);
    } else {
      if (synthetic_transform(plan,input,output,0,&trace,round_value,&description) || !values("tf-output",p,identifier,test,0,output,length)) goto done;
      trace_value("forward",&description,&trace,(double)(clock()-beginning)/CLOCKS_PER_SEC);
      beginning=clock();
      if (synthetic_transform(plan,output,opposite,1,&trace,round_value,&description) || !values("op-output",p,identifier,test,0,opposite,length)) goto done;
      trace_value("opposite",&description,&trace,(double)(clock()-beginning)/CLOCKS_PER_SEC);
    }
    if (fflush(stdout)) goto done;
  }
  success=1;
done:
  if (!success) fprintf(stderr,"numerical profile failed p=%u r=%u profile=%u test=%u\n",p,ring,identifier,description.test);
  unsigned records=1; for (unsigned axis=0;axis<dimension;++axis) records*=axes[axis];
  clear(input,(size_t)records*ring); clear(second,(size_t)records*ring); clear(output,(size_t)records*ring); clear(opposite,(size_t)records*ring);
  synthetic_clear(plan); return success;
}
int main(int argc,char **argv) {
  if (argc!=2) return 43;
#ifdef MUTANT_ZERO
  return 0;
#endif
#ifdef MUTANT_ORACLE_BYPASS
  return system("cat \"${MUL3_ORACLE_PATH}\"");
#endif
  if (!strcmp(argv[1],"child")) {
    if (!children() || !monomials()) return 44;
#ifdef MUTANT_FORCE_EXIT
    return 57;
#else
    return 0;
#endif
  }
  if (strcmp(argv[1],"transform") && strcmp(argv[1],"convolution")) return 43;
  int convolution=!strcmp(argv[1],"convolution");
  const unsigned a[]={2,2},b[]={4,2},c[]={4,2,2},d[]={8,4};
  if (!profile(9,2,a,2,0,convolution) || !profile(9,4,b,2,1,convolution)
      || !profile(33,4,c,3,2,convolution) || !profile(101,8,d,2,3,convolution)) return 45;
  if (ferror(stdout)) return 46;
#ifdef MUTANT_FORCE_EXIT
  return 57;
#else
  return 0;
#endif
}
