#include "network.h"
#include <limits.h>
#include <string.h>

static const unsigned triple_masks[4]={7,11,13,14};
unsigned frame_popcount(uint64_t value) {
  unsigned count=0; while (value) { value&=value-1; ++count; } return count;
}
unsigned frame_role_count(label_field field) { return field==RATIONAL_LABELS ? 320 : 944; }
static unsigned scratch_stride(label_field field) { return field==RATIONAL_LABELS ? 4 : 17; }
exact_status frame_role_at(label_field field, unsigned identity, frame_role *out) {
  if (!out || (field!=RATIONAL_LABELS && field!=BINARY_LABELS) || identity>=frame_role_count(field))
    return EXACT_INVALID;
  memset(out,0,sizeof(*out)); out->identity=identity;
  if (identity<128) {
    out->kind=identity<64 ? DATA_X : DATA_Y;
    unsigned address=identity%64;
    out->coordinates[0]=address/16; out->coordinates[1]=(address/4)%4; out->coordinates[2]=address%4;
    return EXACT_OK;
  }
  unsigned stride=scratch_stride(field), invocation=(identity-128)/stride;
  unsigned local=(identity-128)%stride;
  out->stage=invocation/16;
  unsigned fixed=invocation%16, cursor=0;
  for (unsigned coordinate=0;coordinate<3;++coordinate) if (coordinate!=out->stage)
    out->coordinates[coordinate]=cursor++ ? fixed%4 : fixed/4;
  if (field==BINARY_LABELS && local<12) {
    out->kind=SIDE_ROLE; out->physical_y=local/3;
    out->physical_x=local%3; if (out->physical_x>=out->physical_y) ++out->physical_x;
  } else {
    out->kind=CENTER_ROLE; out->center=local-(field==BINARY_LABELS ? 12 : 0);
  }
  return EXACT_OK;
}
uint64_t frame_tensor_indicator(const unsigned coordinates[3]) {
  uint64_t indicator=0;
  for (unsigned address=0;address<64;++address)
    if ((triple_masks[coordinates[0]]&(1u<<(address/16)))
        && (triple_masks[coordinates[1]]&(1u<<((address/4)%4)))
        && (triple_masks[coordinates[2]]&(1u<<(address%4)))) indicator|=UINT64_C(1)<<address;
  return indicator;
}
static int64_t factor(label_field field, int identity, unsigned triple, unsigned row, unsigned column) {
  if (identity) return row==column ? (field==RATIONAL_LABELS ? 6 : 1) : 0;
  if (!(triple_masks[triple]&(1u<<row))) return 0;
  int selected=(triple_masks[triple]&(1u<<column))!=0;
  return field==RATIONAL_LABELS ? 3*selected-1 : selected;
}
static int64_t tensor_entry(label_field field, const unsigned coordinates[3], unsigned identity_mask,
                            unsigned row, unsigned column) {
  int64_t value=1;
  for (unsigned axis=0;axis<3;++axis) {
    unsigned shift=2*(2-axis);
    value*=factor(field,(identity_mask>>axis)&1,coordinates[axis],(row>>shift)&3,(column>>shift)&3);
  }
  return value;
}
exact_status frame_projection(label_field field, const frame_role *role, unsigned stage,
                              int time, frame_matrix *out) {
  if (!role || !out || stage>2 || (field!=RATIONAL_LABELS && field!=BINARY_LABELS)
      || (time!=-1 && time!=8 && (time<0 || time>7))) return EXACT_INVALID;
  if (role->kind<DATA_X || role->kind>CENTER_ROLE || role->physical_x>3 || role->physical_y>3)
    return EXACT_INVALID;
  for (unsigned axis=0;axis<3;++axis) if (role->coordinates[axis]>3) return EXACT_INVALID;
  out->field=field;
  unsigned coordinates[3]; memcpy(coordinates,role->coordinates,sizeof(coordinates));
  if (role->kind==SIDE_ROLE) coordinates[stage]=(time==2 ? role->physical_x : role->physical_y);
  unsigned previous=(1u<<stage)-1, through=(1u<<(stage+1))-1;
  for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column) {
    int64_t full=row==column ? (field==RATIONAL_LABELS ? 216 : 1) : 0;
    int64_t line=tensor_entry(field,coordinates,0,row,column), value=0;
    if (time==-1) value=role->kind==DATA_X ? line : 0;
    else if (time==8) value=role->kind==DATA_Y ? full-line : full;
    else {
      int64_t all_current=tensor_entry(field,coordinates,through,row,column);
      int64_t prefix_line=tensor_entry(field,coordinates,1u<<stage,row,column);
      int64_t old_current=tensor_entry(field,coordinates,previous,row,column);
      switch (time) {
        case 0: value=old_current-line; break;
        case 1: case 4: value=all_current-prefix_line; break;
        case 2: value=all_current-prefix_line+line; break;
        case 5: value=all_current-line; break;
        default: value=all_current; break;
      }
    }
    out->entries[row][column]=field==BINARY_LABELS ? (int64_t)((uint64_t)value&1) : value;
  }
  return EXACT_OK;
}
exact_status frame_difference(const frame_matrix *head, const frame_matrix *tail, frame_matrix *out) {
  if (!head || !tail || !out || head->field!=tail->field) return EXACT_INVALID;
  frame_matrix result; result.field=head->field;
  for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column) {
    int64_t value;
    if (__builtin_sub_overflow(head->entries[row][column],tail->entries[row][column],&value))
      return EXACT_CAPACITY;
    result.entries[row][column]=head->field==BINARY_LABELS ? (int64_t)((uint64_t)value&1) : value;
  }
  *out=result; return EXACT_OK;
}

typedef frame_fraction rational;
static uint64_t magnitude(int64_t value) { return value<0 ? (uint64_t)(-(value+1))+1 : (uint64_t)value; }
static uint64_t gcd(uint64_t left,uint64_t right) {
  while (right) { uint64_t residue=left%right; left=right; right=residue; } return left;
}
static unsigned bit_length(uint64_t value) { unsigned bits=0; while (value) { ++bits; value>>=1; } return bits; }
static exact_status normalize(rational *value, preparation_work *work) {
  if (!value->denominator || value->numerator==INT64_MIN || value->denominator==INT64_MIN)
    return EXACT_CAPACITY;
  if (value->denominator<0) { value->denominator=-value->denominator; value->numerator=-value->numerator; }
  uint64_t divisor=gcd(magnitude(value->numerator),(uint64_t)value->denominator);
  value->numerator/=(int64_t)divisor; value->denominator/=(int64_t)divisor;
  unsigned bits=bit_length(magnitude(value->numerator)), denominator_bits=bit_length((uint64_t)value->denominator);
  if (denominator_bits>bits) bits=denominator_bits;
  if (bits>work->maximum_rational_bits) work->maximum_rational_bits=bits;
  ++work->rational_operations; return EXACT_OK;
}
static exact_status multiply(rational left, rational right, rational *out, preparation_work *work) {
  uint64_t first=gcd(magnitude(left.numerator),(uint64_t)right.denominator);
  uint64_t second=gcd(magnitude(right.numerator),(uint64_t)left.denominator);
  left.numerator/=(int64_t)first; right.denominator/=(int64_t)first;
  right.numerator/=(int64_t)second; left.denominator/=(int64_t)second;
  rational result;
  if (__builtin_mul_overflow(left.numerator,right.numerator,&result.numerator)
      || __builtin_mul_overflow(left.denominator,right.denominator,&result.denominator)) return EXACT_CAPACITY;
  exact_status status=normalize(&result,work); if (status==EXACT_OK) *out=result; return status;
}
static exact_status subtract(rational left, rational right, rational *out, preparation_work *work) {
  uint64_t divisor=gcd((uint64_t)left.denominator,(uint64_t)right.denominator);
  int64_t first,second; rational result;
  if (__builtin_mul_overflow(left.numerator,right.denominator/(int64_t)divisor,&first)
      || __builtin_mul_overflow(right.numerator,left.denominator/(int64_t)divisor,&second)
      || __builtin_sub_overflow(first,second,&result.numerator)
      || __builtin_mul_overflow(left.denominator,right.denominator/(int64_t)divisor,&result.denominator))
    return EXACT_CAPACITY;
  exact_status status=normalize(&result,work); if (status==EXACT_OK) *out=result; return status;
}
exact_status frame_rational_rank(const frame_matrix *matrix, unsigned *out, preparation_work *work) {
  if (!matrix || !out || !work || matrix->field!=RATIONAL_LABELS) return EXACT_INVALID;
  rational rows[64][64]; unsigned rank=0;
  for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column)
    rows[row][column]=(rational){matrix->entries[row][column],1};
  work->matrix_entries+=4096;
  for (unsigned column=0;column<64 && rank<64;++column) {
    unsigned pivot=rank; while (pivot<64 && !rows[pivot][column].numerator) ++pivot;
    if (pivot==64) continue;
    if (pivot!=rank) for (unsigned entry=column;entry<64;++entry) {
      rational saved=rows[rank][entry]; rows[rank][entry]=rows[pivot][entry]; rows[pivot][entry]=saved;
    }
    rational inverse={rows[rank][column].denominator,rows[rank][column].numerator};
    exact_status status=normalize(&inverse,work); if (status!=EXACT_OK) return status;
    for (unsigned entry=column;entry<64;++entry) {
      status=multiply(rows[rank][entry],inverse,&rows[rank][entry],work); if (status!=EXACT_OK) return status;
    }
    for (unsigned row=rank+1;row<64;++row) if (rows[row][column].numerator) {
      rational coefficient=rows[row][column];
      for (unsigned entry=column;entry<64;++entry) {
        rational product;
        if ((status=multiply(coefficient,rows[rank][entry],&product,work))!=EXACT_OK
            || (status=subtract(rows[row][entry],product,&rows[row][entry],work))!=EXACT_OK) return status;
      }
    }
    ++rank;
  }
  *out=rank; return EXACT_OK;
}

static void rational_identity(rational matrix[64][64]) {
  for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column)
    matrix[row][column]=(rational){row==column,1};
}
static exact_status add(rational left, rational right, rational *out, preparation_work *work) {
  if (right.numerator==INT64_MIN) return EXACT_CAPACITY;
  right.numerator=-right.numerator; return subtract(left,right,out,work);
}
exact_status frame_lower_factorization(const frame_matrix *matrix, frame_factorization *out,
                                       preparation_work *work) {
  if (!matrix || !out || !work || matrix->field!=RATIONAL_LABELS) return EXACT_INVALID;
  frame_factorization result; result.rank=0; result.maximum_coefficient=216;
  rational active[64][64]; unsigned active_rows[64],active_columns[64];
  rational_identity(result.lower_first); rational_identity(result.lower_second);
  for (unsigned row=0;row<64;++row) {
    active_rows[row]=active_columns[row]=1;
    for (unsigned column=0;column<64;++column) {
      active[row][column]=(rational){matrix->entries[row][column],216};
      exact_status status=normalize(&active[row][column],work); if (status!=EXACT_OK) return status;
    }
  }
  while (result.rank<64) {
    unsigned pivot_row=64,pivot_column=64;
    for (unsigned row=0;row<64 && pivot_row==64;++row) if (active_rows[row])
      for (unsigned column=64;column;--column) if (active_columns[column-1] && active[row][column-1].numerator) {
        pivot_row=row; pivot_column=column-1; break;
      }
    if (pivot_row==64) break;
    rational pivot=active[pivot_row][pivot_column],inverse={pivot.denominator,pivot.numerator};
    exact_status status=normalize(&inverse,work); if (status!=EXACT_OK) return status;
    /* Right operations clear columns to the left. Their inverse premultiplies
     * lower_second, so its pivot row receives earlier rows. */
    for (unsigned column=0;column<pivot_column;++column) if (active_columns[column] && active[pivot_row][column].numerator) {
      rational coefficient;
      status=multiply(active[pivot_row][column],inverse,&coefficient,work); if (status!=EXACT_OK) return status;
      for (unsigned row=0;row<64;++row) {
        rational product;
        if ((status=multiply(coefficient,active[row][pivot_column],&product,work))!=EXACT_OK
            || (status=subtract(active[row][column],product,&active[row][column],work))!=EXACT_OK) return status;
      }
      for (unsigned entry=0;entry<64;++entry) {
        rational product;
        if ((status=multiply(coefficient,result.lower_second[column][entry],&product,work))!=EXACT_OK
            || (status=add(result.lower_second[pivot_column][entry],product,&result.lower_second[pivot_column][entry],work))!=EXACT_OK)
          return status;
      }
    }
    /* Scaling the pivot row multiplies the same column of its inverse factor. */
    for (unsigned entry=0;entry<64;++entry) {
      if ((status=multiply(active[pivot_row][entry],inverse,&active[pivot_row][entry],work))!=EXACT_OK
          || (status=multiply(result.lower_first[entry][pivot_row],pivot,&result.lower_first[entry][pivot_row],work))!=EXACT_OK)
        return status;
    }
    for (unsigned row=pivot_row+1;row<64;++row) if (active_rows[row] && active[row][pivot_column].numerator) {
      rational coefficient=active[row][pivot_column];
      for (unsigned entry=0;entry<64;++entry) {
        rational product;
        if ((status=multiply(coefficient,active[pivot_row][entry],&product,work))!=EXACT_OK
            || (status=subtract(active[row][entry],product,&active[row][entry],work))!=EXACT_OK) return status;
      }
      for (unsigned entry=0;entry<64;++entry) {
        rational product;
        if ((status=multiply(coefficient,result.lower_first[entry][row],&product,work))!=EXACT_OK
            || (status=add(result.lower_first[entry][pivot_row],product,&result.lower_first[entry][pivot_row],work))!=EXACT_OK)
          return status;
      }
    }
    result.pivot_rows[result.rank]=pivot_row; result.pivot_columns[result.rank++]=pivot_column;
    active_rows[pivot_row]=active_columns[pivot_column]=0;
  }
  for (unsigned row=0;row<64;++row) for (unsigned column=0;column<64;++column) {
    rational values[]={result.lower_first[row][column],result.lower_second[row][column]};
    for (unsigned index=0;index<2;++index) {
      uint64_t numerator=magnitude(values[index].numerator), denominator=(uint64_t)values[index].denominator;
      if (numerator>result.maximum_coefficient) result.maximum_coefficient=numerator;
      if (denominator>result.maximum_coefficient) result.maximum_coefficient=denominator;
    }
  }
  exact_status status=frame_check_factorization(matrix,&result,work);
  if (status==EXACT_OK) *out=result;
  return status;
}
exact_status frame_check_factorization(const frame_matrix *matrix, const frame_factorization *factor,
                                       preparation_work *work) {
  if (!matrix || !factor || !work || matrix->field!=RATIONAL_LABELS || factor->rank>64) return EXACT_INVALID;
  unsigned used_rows[64]={0},used_columns[64]={0};
  for (unsigned index=0;index<factor->rank;++index) {
    if (factor->pivot_rows[index]>=64 || factor->pivot_columns[index]>=64
        || used_rows[factor->pivot_rows[index]]++ || used_columns[factor->pivot_columns[index]]++) return EXACT_INVALID;
  }
  for (unsigned row=0;row<64;++row) {
    if (!factor->lower_first[row][row].numerator || !factor->lower_second[row][row].numerator) return EXACT_INVALID;
    for (unsigned column=0;column<64;++column) {
      if (column>row && (factor->lower_first[row][column].numerator || factor->lower_second[row][column].numerator))
        return EXACT_INVALID;
      rational reconstructed={0,1};
      for (unsigned index=0;index<factor->rank;++index) {
        rational product; exact_status status;
        if ((status=multiply(factor->lower_first[row][factor->pivot_rows[index]],
                             factor->lower_second[factor->pivot_columns[index]][column],&product,work))!=EXACT_OK
            || (status=add(reconstructed,product,&reconstructed,work))!=EXACT_OK) return status;
      }
      rational expected={matrix->entries[row][column],216};
      exact_status status=normalize(&expected,work); if (status!=EXACT_OK) return status;
      if (reconstructed.numerator!=expected.numerator || reconstructed.denominator!=expected.denominator) return EXACT_INVALID;
    }
  }
  return EXACT_OK;
}
exact_status frame_find_prime(const frame_factorization *factor, uint64_t search_limit, uint64_t *out) {
  if (!factor || !out) return EXACT_INVALID;
  uint64_t candidate=factor->maximum_coefficient+1;
  if (candidate<3) candidate=3;
  if (!(candidate&1)) ++candidate;
  for (;candidate<=search_limit;candidate+=2) {
    int prime=1;
    for (uint64_t divisor=3;divisor<=candidate/divisor;divisor+=2)
      if (candidate%divisor==0) { prime=0; break; }
    if (prime) { *out=candidate; return EXACT_OK; }
  }
  return EXACT_CAPACITY;
}

static uint64_t apply_binary(const frame_matrix *matrix, uint64_t value) {
  uint64_t result=0;
  for (unsigned row=0;row<64;++row) {
    uint64_t mask=0;
    for (unsigned column=0;column<64;++column) if (matrix->entries[row][column]&1)
      mask|=UINT64_C(1)<<column;
    if (frame_popcount(mask&value)&1) result|=UINT64_C(1)<<row;
  }
  return result;
}
static unsigned independent(uint64_t *vectors, unsigned count) {
  uint64_t pivots[64]={0}; unsigned rank=0;
  for (unsigned index=0;index<count;++index) {
    uint64_t value=vectors[index];
    for (unsigned bit=0;bit<64 && value;++bit) if ((value>>bit)&1) {
      if (pivots[bit]) value^=pivots[bit];
      else { pivots[bit]=value; vectors[rank++]=value; break; }
    }
  }
  return rank;
}
exact_status frame_binary_basis(const frame_matrix *matrix, binary_basis *out, preparation_work *work) {
  if (!matrix || !out || !work || matrix->field!=BINARY_LABELS) return EXACT_INVALID;
  uint64_t remaining[64]; unsigned count=0; binary_basis result={0};
  for (unsigned column=0;column<64;++column) {
    uint64_t value=0;
    for (unsigned row=0;row<64;++row) if (matrix->entries[row][column]&1) value|=UINT64_C(1)<<row;
    remaining[count++]=value;
  }
  count=independent(remaining,count);
  while (count) {
    unsigned unit=0; while (unit<count && !(frame_popcount(remaining[unit])&1)) ++unit;
    if (unit<count) {
      uint64_t vector=remaining[unit]; result.vectors[result.length++]=vector;
      remaining[unit]=remaining[--count];
      for (unsigned index=0;index<count;++index) if (frame_popcount(remaining[index]&vector)&1)
        remaining[index]^=vector;
      count=independent(remaining,count); ++work->basis_operations;
    } else {
      if (!result.length) return EXACT_INVALID; /* Nondegenerate alternating residual refuses. */
      uint64_t first=remaining[0]; unsigned mate=1;
      while (mate<count && !(frame_popcount(first&remaining[mate])&1)) ++mate;
      if (mate==count) return EXACT_INVALID;
      uint64_t second=remaining[mate], unit_vector=result.vectors[--result.length];
      result.vectors[result.length++]=unit_vector^first;
      result.vectors[result.length++]=unit_vector^second;
      result.vectors[result.length++]=unit_vector^first^second;
      unsigned kept=0;
      for (unsigned index=1;index<count;++index) if (index!=mate) {
        uint64_t value=remaining[index];
        if (frame_popcount(value&second)&1) value^=first;
        if (frame_popcount(remaining[index]&first)&1) value^=second;
        remaining[kept++]=value;
      }
      count=independent(remaining,kept); ++work->basis_operations;
    }
  }
  exact_status status=frame_check_binary_basis(matrix,&result);
  if (status==EXACT_OK) *out=result;
  return status;
}
exact_status frame_check_binary_basis(const frame_matrix *matrix, const binary_basis *basis) {
  if (!matrix || !basis || matrix->field!=BINARY_LABELS || basis->length>64) return EXACT_INVALID;
  for (unsigned first=0;first<basis->length;++first) {
    if (!(frame_popcount(basis->vectors[first])&1)
        || apply_binary(matrix,basis->vectors[first])!=basis->vectors[first]) return EXACT_INVALID;
    for (unsigned second=0;second<first;++second)
      if (frame_popcount(basis->vectors[first]&basis->vectors[second])&1) return EXACT_INVALID;
  }
  for (unsigned column=0;column<64;++column) {
    uint64_t expected=apply_binary(matrix,UINT64_C(1)<<column), actual=0;
    for (unsigned index=0;index<basis->length;++index) if ((basis->vectors[index]>>column)&1)
      actual^=basis->vectors[index];
    if (actual!=expected) return EXACT_INVALID;
  }
  return EXACT_OK;
}
unsigned frame_binary_phase(const frame_matrix *matrix, uint64_t frequency) {
  return frame_popcount(apply_binary(matrix,frequency))%4;
}
exact_status frame_profile_admit(unsigned ground_dimension, label_field field, uint64_t role_budget) {
  if (field!=RATIONAL_LABELS && field!=BINARY_LABELS) return EXACT_INVALID;
  if (ground_dimension<3) return EXACT_INVALID;
  if (ground_dimension==9 && field==RATIONAL_LABELS) return EXACT_INVALID;
  if (ground_dimension!=4) return EXACT_CAPACITY;
  return role_budget>=frame_role_count(field) ? EXACT_OK : EXACT_CAPACITY;
}
