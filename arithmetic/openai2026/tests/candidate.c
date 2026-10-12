#include "exact.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int64_t ordinary(unsigned test, size_t field, unsigned channel) {
  return (int64_t)((test*19+field*7+channel*11)%23)-11;
}
static int64_t initial(unsigned test, size_t field, unsigned channel, size_t *scale) {
  *scale=2;
  if (test>=35) {
    unsigned index=test-35, seed=index<12 ? index : 17;
    if (channel) return 0;
    if (field<20) {
      if (index>=12) { *scale=0; return field==index-12; }
      return ordinary(seed,field,0);
    }
    if (field<40) return ordinary(seed,field-20,0);
    if (field<240) return ordinary(seed+3,field-40+1,0);
    if (field<246) return ordinary(seed+5,field-240,0);
    *scale=1; return seed+7;
  }
  int64_t value=ordinary(test,field,channel);
  if (field<20) {
    if (test>=12 && test<32) return field==test-12 ? (channel ? -1 : 1) : 0;
    if (test==32) return 0;
    if (test>=33) return (test==33 ? 1 : -1)*(INT64_C(1099511627776)+UINT32_MAX+value);
  }
  return value;
}
static int equals(const exact_dyadic *v, const char *hex) {
  unsigned char bytes[8]; char actual[17];
  if (exact_serialize(v,0,bytes,8)!=EXACT_OK) return 0;
  for (unsigned i=0;i<8;++i) sprintf(actual+2*i,"%02x",bytes[i]);
  return !strcmp(actual,hex);
}
static int primitives(void) {
  exact_dyadic a={0},b={0},out={0},small={0}; int ok=0,order=7;
  if (exact_init(&a,8) || exact_init(&b,8) || exact_init(&out,8) || exact_init(&small,1)) goto done;
  if (exact_set(&a,INT64_MAX,0) || exact_set(&b,1,0) || exact_add(&out,&a,&b)
      || out.length!=2 || out.limbs[0]!=0 || out.limbs[1]!=UINT32_C(0x80000000)) goto done;
  if (exact_set(&a,7,2) || exact_truncate(&out,&a,0) || !equals(&out,"0000000000000001")) goto done;
  if (exact_set(&a,-7,2) || exact_truncate(&out,&a,0) || !equals(&out,"ffffffffffffffff")) goto done;
  if (exact_set(&small,UINT32_MAX,0) || exact_add(&small,&small,&b)!=EXACT_CAPACITY
      || small.length!=1 || small.limbs[0]!=UINT32_MAX) goto done;
  if (exact_set(&a,-1,0) || exact_set(&b,1,1) || exact_add(&out,&a,&b)
      || out.sign!=-1 || out.length!=1 || out.limbs[0]!=1 || out.binary_scale!=1) goto done;
  if (exact_compare(&order,&out,&a) || order!=1) goto done;
  if (exact_set(&a,1,SIZE_MAX) || exact_half(&out,&a)!=EXACT_CAPACITY) goto done;
  if (exact_set(&a,INT64_MIN,0) || !equals(&a,"8000000000000000")) goto done;
  exact_dyadic alias=a;
  if (exact_add(&out,&a,&alias)!=EXACT_INVALID) goto done;
  if (exact_serialize(&a,0,(uint8_t *)a.limbs,8)!=EXACT_INVALID) goto done;
  if (exact_set(&a,3,1) || exact_shift(&out,&a,33) || out.length!=2
      || out.limbs[0]!=0 || out.limbs[1]!=3 || out.binary_scale!=0) goto done;
  unsigned char sentinel[1]={0x55};
  if (exact_set(&a,128,0) || exact_serialize(&a,0,sentinel,1)!=EXACT_CAPACITY || sentinel[0]!=0x55) goto done;
  if (exact_set(&a,-128,0) || exact_serialize(&a,0,sentinel,1) || sentinel[0]!=0x80) goto done;
  if (exact_set(&a,-129,0) || exact_serialize(&a,0,sentinel,1)!=EXACT_CAPACITY || sentinel[0]!=0x80) goto done;
  if (exact_set(&a,-3,2) || exact_set(&b,-7,3) || exact_compare(&order,&a,&b) || order!=1) goto done;
  ok=1;
done:
  exact_clear(&a); exact_clear(&b); exact_clear(&out); exact_clear(&small); return ok;
}
static int refusal(void) {
  scalar_network n; if (scalar_init(&n,1)) return 0;
  if (exact_set(&n.target[0].real,UINT32_MAX,0) || exact_set(&n.source[0].real,1,0)) { scalar_clear(&n); return 0; }
  exact_status status=scalar_execute(&n,0);
  int ok=status==EXACT_CAPACITY && n.target[0].real.limbs[0]==UINT32_MAX
    && n.source[0].real.limbs[0]==1 && n.side[0].real.sign==0;
  uint32_t *saved=n.side[0].real.limbs;
  n.side[0].real.limbs=n.source[0].real.limbs;
  ok &= scalar_execute(&n,0)==EXACT_INVALID;
  n.side[0].real.limbs=saved; scalar_clear(&n); return ok;
}
static exact_status stage_record(void *context, unsigned step, const scalar_network *n) {
  unsigned test=*(unsigned *)context;
  for (size_t field=0;field<SCALAR_FIELDS;++field) for (unsigned channel=0;channel<2;++channel) {
    const exact_gaussian *g=scalar_const_field(n,field); unsigned char bytes[8];
    if (exact_serialize(channel ? &g->imaginary : &g->real,4,bytes,8)) return EXACT_INVALID;
#ifdef MUTANT_ZERO
    memset(bytes,0,sizeof(bytes));
#endif
    printf("stage\t%u\t%u\t%zu\t%u\t",step,test,field,channel);
    for (unsigned i=0;i<8;++i) printf("%02x",bytes[i]);
    putchar('\n');
  }
  return ferror(stdout) ? EXACT_INVALID : EXACT_OK;
}
int main(void) {
#ifdef MUTANT_ORACLE_BYPASS
  return system("cat \"$SCALAR_ORACLE_OUTPUT\"");
#endif
  if (!primitives() || !refusal()) return 40;
  for (unsigned route=0;route<3;++route) for (unsigned test=0;test<67;++test) {
    scalar_network n; if (scalar_init(&n,8)) return 41;
    for (size_t field=0;field<SCALAR_FIELDS;++field) for (unsigned channel=0;channel<2;++channel) {
      exact_gaussian *g=scalar_field(&n,field); size_t scale;
      int64_t numerator=initial(test,field,channel,&scale);
      if (exact_set(channel ? &g->imaginary : &g->real,numerator,scale)) { scalar_clear(&n); return 42; }
    }
    exact_status status=route==2 ? scalar_signed_swap(&n) : scalar_execute(&n,route);
    if (status!=EXACT_OK) { scalar_clear(&n); return 43; }
    for (size_t field=0;field<SCALAR_FIELDS;++field) for (unsigned channel=0;channel<2;++channel) {
      exact_gaussian *g=scalar_field(&n,field); unsigned char bytes[8];
      if (exact_serialize(channel ? &g->imaginary : &g->real,4,bytes,8)) { scalar_clear(&n); return 44; }
#ifdef MUTANT_ZERO
      memset(bytes,0,sizeof(bytes));
#endif
      printf("%u\t%u\t%zu\t%u\t",route,test,field,channel);
      for (unsigned i=0;i<8;++i) printf("%02x",bytes[i]);
      putchar('\n');
    }
    scalar_clear(&n);
  }
  for (unsigned test=35;test<67;++test) {
    scalar_network n; if (scalar_init(&n,8)) return 41;
    for (size_t field=0;field<SCALAR_FIELDS;++field) for (unsigned channel=0;channel<2;++channel) {
      exact_gaussian *g=scalar_field(&n,field); size_t scale;
      int64_t numerator=initial(test,field,channel,&scale);
      if (exact_set(channel ? &g->imaginary : &g->real,numerator,scale)) { scalar_clear(&n); return 42; }
    }
    exact_status status=scalar_execute_observed(&n,0,stage_record,&test);
    scalar_clear(&n); if (status!=EXACT_OK) return 46;
  }
  return ferror(stdout) ? 45 : 0;
}
