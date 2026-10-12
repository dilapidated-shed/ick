#include "exact_internal.h"
#include <string.h>

exact_gaussian *scalar_field(scalar_network *n, size_t i) {
  if (!n || i>=SCALAR_FIELDS) return NULL;
  if (i<20) return &n->source[i];
  if (i<40) return &n->target[i-20];
  if (i<240) return &n->side[i-40];
  if (i<246) return &n->central[i-240];
  return &n->star;
}
const exact_gaussian *scalar_const_field(const scalar_network *n, size_t i) {
  return scalar_field((scalar_network *)n,i);
}
static exact_dyadic *channel(exact_gaussian *g, unsigned c) {
  return c ? &g->imaginary : &g->real;
}
void scalar_clear(scalar_network *n) {
  if (!n) return;
  for (size_t i=0;i<SCALAR_FIELDS;++i) {
    exact_gaussian *g=scalar_field(n,i); exact_clear(&g->real); exact_clear(&g->imaginary);
  }
}
exact_status scalar_init(scalar_network *n, size_t capacity) {
  if (!n) return EXACT_INVALID;
  memset(n,0,sizeof(*n));
  for (size_t i=0;i<SCALAR_FIELDS;++i) for (unsigned c=0;c<2;++c) {
    exact_status status=exact_init(channel(scalar_field(n,i),c),capacity);
    if (status!=EXACT_OK) { scalar_clear(n); return status; }
  }
  return EXACT_OK;
}
static exact_status validate(const scalar_network *n) {
  if (!n) return EXACT_INVALID;
  for (size_t i=0;i<2*SCALAR_FIELDS;++i) {
    const exact_gaussian *g=scalar_const_field(n,i/2);
    const exact_dyadic *a=i%2 ? &g->imaginary : &g->real;
    if (!exact_valid(a)) return EXACT_INVALID;
    for (size_t j=0;j<i;++j) {
      const exact_gaussian *h=scalar_const_field(n,j/2);
      const exact_dyadic *b=j%2 ? &h->imaginary : &h->real;
      if (exact_alias_invalid(a,b)) return EXACT_INVALID;
    }
  }
  return EXACT_OK;
}
static exact_status clone(scalar_network *out, const scalar_network *in) {
  memset(out,0,sizeof(*out)); exact_status status=validate(in);
  if (status!=EXACT_OK) return status;
  for (size_t i=0;i<SCALAR_FIELDS;++i) for (unsigned c=0;c<2;++c) {
    const exact_gaussian *g=scalar_const_field(in,i);
    const exact_dyadic *a=c ? &g->imaginary : &g->real;
    exact_dyadic *b=channel(scalar_field(out,i),c);
    if ((status=exact_init(b,a->capacity))!=EXACT_OK || (status=exact_copy(b,a))!=EXACT_OK) {
      scalar_clear(out); return status;
    }
  }
  return EXACT_OK;
}
static void commit(scalar_network *out, const scalar_network *in) {
  for (size_t i=0;i<SCALAR_FIELDS;++i) {
    const exact_gaussian *a=scalar_const_field(in,i); exact_gaussian *b=scalar_field(out,i);
    (void)exact_copy(&b->real,&a->real); (void)exact_copy(&b->imaginary,&a->imaginary);
  }
}
static unsigned popcount(unsigned bits) {
  unsigned count=0; while (bits) { count+=bits&1; bits>>=1; } return count;
}
static int neighbor(unsigned a, unsigned b) {
  unsigned overlap=popcount(a&b); return a!=b && (overlap==0 || overlap==2);
}
static exact_status accumulate(exact_dyadic *out, const exact_dyadic *in, int sign) {
  return sign>0 ? exact_add(out,out,in) : exact_subtract(out,out,in);
}
static exact_status schedule(scalar_network *n, int inverse) {
  unsigned triples[20], count=0;
  for (unsigned a=0;a<6;++a) for (unsigned b=a+1;b<6;++b) for (unsigned c=b+1;c<6;++c)
    triples[count++]=(1u<<a)|(1u<<b)|(1u<<c);
  for (unsigned phase=0;phase<8;++phase) {
    unsigned step=inverse ? 7-phase : phase; int direction=inverse ? -1 : 1;
#ifdef MUTANT_OMITTED_UNDO
    if (step==7) continue;
#endif
    for (unsigned c=0;c<2;++c) {
      if (step==0 || step==5 || step==2 || step==7) {
        size_t side=0;
        for (unsigned s=0;s<20;++s) for (unsigned t=0;t<20;++t) if (neighbor(triples[s],triples[t])) {
          exact_dyadic *aux=channel(&n->side[side++],c);
          exact_status status;
          if (step==2 || step==7) {
            status=accumulate(aux,channel(&n->source[t],c),direction*(step==2 ? 1 : -1));
          } else {
            exact_dyadic half={0}; exact_dyadic *out=channel(&n->target[s],c);
            status=exact_init(&half,out->capacity);
            if (status==EXACT_OK) status=exact_half(&half,aux);
            int coefficient=popcount(triples[s]&triples[t])==0 ? 1 : -1;
#ifdef MUTANT_WRONG_SIDE_SIGN
            coefficient=-coefficient;
#endif
            if (status==EXACT_OK) status=accumulate(out,&half,direction*(step==0 ? -1 : 1)*coefficient);
            exact_clear(&half);
          }
          if (status!=EXACT_OK) return status;
        }
      } else if (step==1 || step==4) {
        for (unsigned s=0;s<20;++s) {
          exact_dyadic *out=channel(&n->target[s],c), sum={0};
          exact_status status=exact_init(&sum,out->capacity);
          for (unsigned i=0;i<6 && status==EXACT_OK;++i) if (triples[s]&(1u<<i))
            status=accumulate(&sum,channel(&n->central[i],c),1);
          if (status==EXACT_OK) status=accumulate(&sum,channel(&n->star,c),-1);
          if (status==EXACT_OK) status=exact_half(&sum,&sum);
          if (status==EXACT_OK) status=accumulate(out,&sum,direction*(step==1 ? -1 : 1));
          exact_clear(&sum); if (status!=EXACT_OK) return status;
        }
      } else {
        for (unsigned t=0;t<20;++t) {
          exact_dyadic *in=channel(&n->source[t],c);
          int sign=direction*(step==3 ? 1 : -1);
          for (unsigned i=0;i<6;++i) if (triples[t]&(1u<<i)) {
            exact_status status=accumulate(channel(&n->central[i],c),in,sign);
            if (status!=EXACT_OK) return status;
          }
          exact_status status=accumulate(channel(&n->star,c),in,sign);
          if (status!=EXACT_OK) return status;
        }
      }
    }
  }
  return EXACT_OK;
}
exact_status scalar_execute(scalar_network *n, int inverse) {
  if (inverse!=0 && inverse!=1) return EXACT_INVALID;
  scalar_network work; exact_status status=clone(&work,n);
  if (status!=EXACT_OK) return status;
  status=schedule(&work,inverse); if (status==EXACT_OK) commit(n,&work);
  scalar_clear(&work); return status;
}
static void exchange(scalar_network *n) {
  for (size_t i=0;i<20;++i) {
    exact_gaussian temporary=n->source[i]; n->source[i]=n->target[i]; n->target[i]=temporary;
  }
}
exact_status scalar_signed_swap(scalar_network *n) {
  scalar_network work; exact_status status=clone(&work,n);
  if (status!=EXACT_OK) return status;
  status=schedule(&work,0);
  if (status==EXACT_OK) { exchange(&work); status=schedule(&work,1); }
  if (status==EXACT_OK) { exchange(&work); status=schedule(&work,0); }
  if (status==EXACT_OK) commit(n,&work);
  scalar_clear(&work); return status;
}
