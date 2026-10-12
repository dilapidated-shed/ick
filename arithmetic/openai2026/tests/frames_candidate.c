#include "network.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static exact_status integer_product(exact_dyadic *out, const exact_dyadic *left, uint64_t right) {
  exact_dyadic result={0},term={0}; exact_status status=exact_init(&result,out->capacity);
  if (status!=EXACT_OK) return status;
  status=exact_init(&term,out->capacity);
  for (unsigned bit=0;right && status==EXACT_OK;++bit,right>>=1) if (right&1) {
    status=exact_shift(&term,left,bit);
    if (status==EXACT_OK) status=exact_add(&result,&result,&term);
  }
  if (status==EXACT_OK) status=exact_copy(out,&result);
  exact_clear(&result); exact_clear(&term); return status;
}
static void decimal(const exact_dyadic *value) {
  uint32_t words[8]={0}; size_t length=value->length; char digits[80]; unsigned count=0;
  memcpy(words,value->limbs,length*sizeof(uint32_t));
  do {
    uint64_t residue=0;
    for (size_t index=length;index;--index) {
      uint64_t current=(residue<<32)|words[index-1];
      words[index-1]=(uint32_t)(current/10); residue=current%10;
    }
    digits[count++]=(char)('0'+residue);
    while (length && !words[length-1]) --length;
  } while (length);
  while (count) putchar(digits[--count]);
}
static int summary(unsigned ground_dimension) {
  uint64_t triples=(uint64_t)ground_dimension*(ground_dimension-1)*(ground_dimension-2)/6;
  uint64_t pairs=triples*triples*triples, invocations=3*triples*triples;
  uint64_t dimension=(uint64_t)ground_dimension*ground_dimension*ground_dimension;
  uint64_t bit_neighbors=3*(uint64_t)(ground_dimension-3)*(ground_dimension-4)/2;
  uint64_t remaining=ground_dimension-3;
  uint64_t complex_neighbors=(remaining>=3 ? remaining*(remaining-1)*(remaining-2)/6 : 0)+3*remaining;
  const char *names[]={"triples","data_pairs","invocations","ground_slots","bit_neighbors","complex_neighbors",
                       "bit_roles","complex_roles","bit_loss","complex_loss","bit_rank","complex_rank"};
  exact_dyadic values[12]={{0}},temporary={0}; int success=0;
  for (unsigned index=0;index<12;++index) if (exact_init(&values[index],8)) goto done;
  if (exact_init(&temporary,8)) goto done;
  uint64_t small[]={triples,pairs,invocations,dimension,bit_neighbors,complex_neighbors};
  for (unsigned index=0;index<6;++index) if (exact_set(&values[index],(int64_t)small[index],0)) goto done;
  for (unsigned field=0;field<2;++field) {
    uint64_t center=ground_dimension+field, neighbors=field ? complex_neighbors : bit_neighbors;
    if (exact_set(&temporary,(int64_t)(triples*neighbors+center),0)
        || integer_product(&values[6+field],&temporary,invocations)
        || exact_shift(&temporary,&values[1],1)
        || exact_add(&values[6+field],&values[6+field],&temporary)
        || exact_set(&values[8+field],(int64_t)(invocations*center*ground_dimension),0)
        || integer_product(&values[10+field],&values[6+field],dimension)
        || exact_shift(&temporary,&values[1],field ? 1 : 0)
        || exact_subtract(&values[10+field],&values[10+field],&temporary)
        || exact_shift(&temporary,&values[8+field],1)
        || exact_add(&values[10+field],&values[10+field],&temporary)) goto done;
  }
  for (unsigned index=0;index<12;++index) {
    printf("count\t%u\t%s\t",ground_dimension,names[index]); decimal(&values[index]); putchar('\n');
  }
  success=1;
done:
  for (unsigned index=0;index<12;++index) exact_clear(&values[index]);
  exact_clear(&temporary); return success;
}

typedef struct { uint64_t hash; frame_matrix matrix; unsigned rank; binary_basis basis; } cached_certificate;
enum { CERTIFICATE_CACHE_BUDGET = 4096 };
static cached_certificate *cache;
static unsigned cache_length;
static preparation_work preparation;
static uint64_t cache_hits, maximum_factor_coefficient=216, factorizations;
static uint64_t matrix_hash(const frame_matrix *matrix) {
  uint64_t hash=UINT64_C(1469598103934665603)^matrix->field;
  for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column)
    hash=(hash^(uint64_t)matrix->entries[row][column])*UINT64_C(1099511628211);
  return hash;
}
static exact_status certificate(const frame_matrix *matrix, unsigned *rank) {
  uint64_t hash=matrix_hash(matrix);
  for (unsigned index=0;index<cache_length;++index)
    if (cache[index].hash==hash && cache[index].matrix.field==matrix->field
        && !memcmp(cache[index].matrix.entries,matrix->entries,sizeof(matrix->entries))) {
      ++cache_hits; *rank=cache[index].rank; return EXACT_OK;
    }
  if (cache_length==CERTIFICATE_CACHE_BUDGET) return EXACT_CAPACITY;
  cached_certificate *item=&cache[cache_length]; item->hash=hash; item->matrix=*matrix;
  exact_status status;
  if (matrix->field==RATIONAL_LABELS) {
    status=frame_rational_rank(matrix,&item->rank,&preparation);
    if (status==EXACT_OK) {
      frame_factorization factor;
      status=frame_lower_factorization(matrix,&factor,&preparation);
      if (status==EXACT_OK && factor.rank!=item->rank) status=EXACT_INVALID;
      if (status==EXACT_OK) {
        uint64_t prime=0,h[64],d[64],interchanges=0;
        status=frame_find_prime(&factor,UINT64_C(1000000),&prime);
        if (status!=EXACT_OK) return status;
        for (unsigned coordinate=0;coordinate<64;++coordinate) { h[coordinate]=(coordinate*17+3)%prime; d[coordinate]=(coordinate*11+7)%prime; }
        if (status==EXACT_OK) status=frame_apply_shear(matrix,&factor,prime,1,h,d,&interchanges);
        if (status==EXACT_OK && interchanges!=item->rank) status=EXACT_INVALID;
      }
      if (status==EXACT_OK) {
        ++factorizations;
        if (factor.maximum_coefficient>maximum_factor_coefficient) maximum_factor_coefficient=factor.maximum_coefficient;
      }
    }
  }
  else {
    status=frame_binary_basis(matrix,&item->basis,&preparation); item->rank=item->basis.length;
    if (status==EXACT_OK) status=frame_check_binary_basis(matrix,&item->basis);
  }
  if (status!=EXACT_OK) return status;
  *rank=item->rank; ++cache_length; return EXACT_OK;
}
static exact_status vertex(label_field field, const frame_role *role, int node, frame_matrix *out) {
  unsigned stage=node<0 ? 0 : node==24 ? 2 : (unsigned)node/8;
  int time=node<0 ? -1 : node==24 ? 8 : node%8;
  exact_status status=frame_projection(field,role,stage,time,out);
  if (status==EXACT_OK && field==RATIONAL_LABELS && role->kind==DATA_X && node==-1)
    for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column)
      out->entries[row][column]=-out->entries[row][column];
#ifdef MUTANT_SOURCE_RANK
  if (status==EXACT_OK && field==RATIONAL_LABELS && role->kind==DATA_X && node==-1)
    for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column)
      out->entries[row][column]=-out->entries[row][column];
#endif
  return status;
}
static int inspect_role(label_field field, unsigned identity) {
  frame_role role; if (frame_role_at(field,identity,&role)) return 0;
  int nodes[14], count=0; nodes[count++]=-1;
  if (role.kind==DATA_X || role.kind==DATA_Y) {
    const unsigned x_times[]={2,3,6,7}, y_times[]={0,1,4,5};
    const unsigned *times=role.kind==DATA_X ? x_times : y_times;
    for (unsigned stage=0;stage<3;++stage) for (unsigned index=0;index<4;++index)
      nodes[count++]=(int)(8*stage+times[index]);
  } else {
    const unsigned side_times[]={0,2,5,7}, center_times[]={1,3,4,6};
    const unsigned *times=role.kind==SIDE_ROLE ? side_times : center_times;
    for (unsigned index=0;index<4;++index) nodes[count++]=(int)(8*role.stage+times[index]);
  }
  nodes[count++]=24;
  frame_matrix tail,head,difference;
  if (vertex(field,&role,nodes[0],&tail)) return 0;
  for (int index=1;index<count;++index) {
    if (vertex(field,&role,nodes[index],&head) || frame_difference(&head,&tail,&difference)) return 0;
    unsigned rank; exact_status status=certificate(&difference,&rank);
    if (status!=EXACT_OK) {
      fprintf(stderr,"certificate refusal: field=%u role=%u edge=%d,%d status=%u\n",
              field,identity,nodes[index-1],nodes[index],status); return 0;
    }
    int decreasing=role.kind==CENTER_ROLE && nodes[index-1]%8==3 && nodes[index]%8==4;
    int direction=!rank ? 0 : decreasing ? -1 : 1;
    printf("edge\t%s\t%u\t%d\t%d\t%u\t%d\n",field==RATIONAL_LABELS ? "rational" : "binary",
           identity,nodes[index-1],nodes[index],rank,direction);
    tail=head;
  }
  return 1;
}
static int inspect_endpoint(label_field field, unsigned identity) {
  frame_role input,output; unsigned destination=frame_route_target(identity);
  if (frame_role_at(field,identity,&input) || frame_role_at(field,destination,&output)) return 0;
  frame_matrix source,sink,difference;
  if (vertex(field,&input,-1,&source) || vertex(field,&output,24,&sink)) return 0;
  int sign=field==BINARY_LABELS ? frame_route_sign(input.kind) : 1;
  if (field==RATIONAL_LABELS) {
    if (frame_difference(&sink,&source,&difference)) return 0;
    for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column)
      if (difference.entries[row][column]!=(row==column ? 216 : 0)) return 0;
  } else {
    uint64_t frequencies[]={0,1,UINT64_C(123456789),UINT64_MAX,frame_tensor_indicator(input.coordinates)};
    for (unsigned index=0;index<5;++index) {
      uint64_t frequency=frequencies[index],shifted=frequency;
      if (input.kind==DATA_X) shifted^=frame_tensor_indicator(input.coordinates);
      unsigned actual=(frame_binary_phase(&sink,shifted)+4-frame_binary_phase(&source,shifted)
                       +(input.kind==DATA_X ? 27 : 0))%4;
      if (actual!=frame_popcount(frequency)%4) return 0;
    }
  }
  printf("endpoint\t%s\t%u\t%u\t%d\n",field==RATIONAL_LABELS ? "rational" : "binary",identity,destination,sign);
  return 1;
}
int main(void) {
  if (frame_profile_admit(9,RATIONAL_LABELS,1000)!=EXACT_INVALID
      || frame_profile_admit(100,BINARY_LABELS,UINT64_MAX)!=EXACT_CAPACITY
      || frame_profile_admit(4,BINARY_LABELS,943)!=EXACT_CAPACITY) return 40;
  /* Complementary h=6 triples leave a nonzero alternating residual. It has
   * no orthonormal basis and is not silently admitted as a phase profile. */
  frame_matrix alternating={0}; alternating.field=BINARY_LABELS;
  for (unsigned row=0;row<6;++row) for (unsigned column=0;column<6;++column)
    alternating.entries[row][column]=(row==column)^((row<3)==(column<3));
  binary_basis refused_basis={0}; preparation_work refusal_work={0};
  if (frame_binary_basis(&alternating,&refused_basis,&refusal_work)!=EXACT_INVALID) return 47;
  if (!summary(4) || !summary(100)) return 41;
  cache=calloc(CERTIFICATE_CACHE_BUDGET,sizeof(*cache)); if (!cache) return 42;
  for (unsigned field=0;field<2;++field) for (unsigned role=0;role<frame_role_count(field);++role)
    if (!inspect_role(field,role)) { free(cache); return 43; }
  for (unsigned field=0;field<2;++field) for (unsigned role=0;role<frame_role_count(field);++role)
    if (!inspect_endpoint(field,role)) { free(cache); return 46; }
  frame_factorization prime_bound={0}; prime_bound.maximum_coefficient=maximum_factor_coefficient;
  uint64_t prime=0;
  if (frame_find_prime(&prime_bound,UINT64_C(1000000),&prime)!=EXACT_OK) { free(cache); return 45; }
  fprintf(stderr,"preparation\tcertificates=%u\tcache_hits=%llu\tcache_bytes=%llu\trational_operations=%llu\tmaximum_rational_bits=%llu\tbasis_operations=%llu\tfactorizations=%llu\tprime=%llu\tallocated_cache_bytes=%llu\n",
          cache_length,(unsigned long long)cache_hits,(unsigned long long)(cache_length*sizeof(*cache)),
          (unsigned long long)preparation.rational_operations,(unsigned long long)preparation.maximum_rational_bits,
          (unsigned long long)preparation.basis_operations,(unsigned long long)factorizations,(unsigned long long)prime,
          (unsigned long long)(CERTIFICATE_CACHE_BUDGET*sizeof(*cache)));
  free(cache); return ferror(stdout) ? 44 : 0;
}
