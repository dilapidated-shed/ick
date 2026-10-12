#include "layout.h"
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t value; unsigned width; } binary_counter;
static binary_counter counter_start(size_t range, stream_work *work) {
  unsigned width=0; size_t remaining=range>1 ? range-1 : 1;
  do { ++width; remaining>>=1; } while (remaining);
  work->counter_moves+=2*width; return (binary_counter){0,width};
}
static void counter_advance(binary_counter *counter, stream_work *work) {
  unsigned changed=1;
  while (changed<counter->width && ((counter->value>>(changed-1))&1)) ++changed;
  work->counter_moves+=2*changed; ++counter->value;
}
static int volume(size_t prefixes, size_t rows, size_t suffix, size_t *out) {
  size_t first;
  return prefixes && rows && suffix && !__builtin_mul_overflow(prefixes,rows,&first)
    && !__builtin_mul_overflow(first,suffix,out);
}
void stream_clear(role_stream *streams, size_t roles) {
  if (!streams) return;
  for (size_t role=0;role<roles;++role) { free(streams[role].records); streams[role]=(role_stream){0}; }
}
exact_status stream_split_rows(const uint64_t *input, size_t length, size_t prefixes, size_t rows,
                               size_t suffix, size_t roles, role_stream *out, stream_work *work) {
  size_t total;
  if (!input || !out || !work || !roles || rows%roles || !volume(prefixes,rows,suffix,&total)
      || total!=length || total>SIZE_MAX/sizeof(uint64_t)) return EXACT_INVALID;
  role_stream *temporary=calloc(roles,sizeof(*temporary)); if (!temporary) return EXACT_ALLOCATION;
  size_t per_role=total/roles;
  for (size_t role=0;role<roles;++role) {
    temporary[role].records=calloc(per_role,sizeof(uint64_t));
    if (!temporary[role].records) { stream_clear(temporary,roles); free(temporary); return EXACT_ALLOCATION; }
    temporary[role].length=per_role;
  }
  binary_counter rank=counter_start(total,work);
  for (size_t prefix=0;prefix<prefixes;++prefix) for (size_t row=0;row<rows;++row)
    for (size_t tail=0;tail<suffix;++tail) {
      size_t destination=(prefix*(rows/roles)+row/roles)*suffix+tail;
      temporary[row%roles].records[destination]=input[rank.value];
      work->tape_moves+=2; ++work->records; counter_advance(&rank,work);
    }
  work->tape_moves+=2*total; /* Rewind the input and all visited role-stream cells. */
  memcpy(out,temporary,roles*sizeof(*out)); free(temporary); return EXACT_OK;
}
exact_status stream_merge_rows(const role_stream *streams, size_t roles, const size_t *order,
                               size_t prefixes, size_t rows, size_t suffix,
                               uint64_t *out, size_t capacity, stream_work *work) {
  size_t total;
  if (!streams || !order || !out || !work || !roles || rows%roles
      || !volume(prefixes,rows,suffix,&total)) return EXACT_INVALID;
  if (capacity<total || total>SIZE_MAX/sizeof(uint64_t)) return EXACT_CAPACITY;
  for (size_t role=0;role<roles;++role) {
    if (order[role]>=roles || !streams[role].records || streams[role].length!=total/roles) return EXACT_INVALID;
    for (size_t earlier=0;earlier<role;++earlier) if (order[role]==order[earlier]) return EXACT_INVALID;
  }
  uint64_t *temporary=calloc(total,sizeof(uint64_t)); if (!temporary) return EXACT_ALLOCATION;
  binary_counter rank=counter_start(total,work);
  for (size_t prefix=0;prefix<prefixes;++prefix) for (size_t row=0;row<rows;++row)
    for (size_t tail=0;tail<suffix;++tail) {
      size_t source=(prefix*(rows/roles)+row/roles)*suffix+tail;
      temporary[rank.value]=streams[order[row%roles]].records[source];
      work->tape_moves+=2; ++work->records; counter_advance(&rank,work);
    }
  memcpy(out,temporary,total*sizeof(uint64_t)); free(temporary);
  work->tape_moves+=2*total; return EXACT_OK;
}
exact_status stream_pad_width(const uint64_t *input, size_t prefixes, size_t width, size_t suffix,
                              size_t padded_width, uint64_t *out, size_t capacity, stream_work *work) {
  size_t total;
  if (!input || !out || !work || padded_width<width || !volume(prefixes,padded_width,suffix,&total))
    return EXACT_INVALID;
  if (capacity<total || total>SIZE_MAX/sizeof(uint64_t)) return EXACT_CAPACITY;
  uint64_t *temporary=calloc(total,sizeof(uint64_t)); if (!temporary) return EXACT_ALLOCATION;
  for (size_t prefix=0;prefix<prefixes;++prefix) for (size_t column=0;column<width;++column)
    for (size_t tail=0;tail<suffix;++tail) {
      temporary[(prefix*padded_width+column)*suffix+tail]=input[(prefix*width+column)*suffix+tail];
      work->tape_moves+=2;
    }
  memcpy(out,temporary,total*sizeof(uint64_t)); free(temporary); work->tape_moves+=2*total;
  return EXACT_OK;
}
