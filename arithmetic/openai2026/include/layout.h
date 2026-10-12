#ifndef OPENAI2026_LAYOUT_H
#define OPENAI2026_LAYOUT_H
#include "exact.h"
#include <stdint.h>
typedef struct { uint64_t tape_moves, counter_moves, ram_operations, records; } stream_work;
typedef struct { uint64_t *records; size_t length; } role_stream;
exact_status stream_split_rows(const uint64_t *, size_t, size_t prefixes, size_t rows,
                               size_t suffix, size_t roles, role_stream *, stream_work *);
exact_status stream_merge_rows(const role_stream *, size_t roles, const size_t *class_order,
                               size_t prefixes, size_t rows, size_t suffix,
                               uint64_t *, size_t capacity, stream_work *);
void stream_clear(role_stream *, size_t roles);
exact_status stream_pad_width(const uint64_t *, size_t prefixes, size_t width, size_t suffix,
                              size_t padded_width, uint64_t *, size_t capacity, stream_work *);
exact_status layout_interchange(uint64_t *earlier, uint64_t *later, size_t dimension,
                                uint64_t modulus, stream_work *);
typedef struct { unsigned guard_width, selected_count, first_bit; } packed_layout;
typedef struct { uint64_t control, target, scratch; } packed_address;
exact_status packed_admit(packed_layout, unsigned *chunk_width);
exact_status packed_rotations(packed_layout, packed_address *, int inverse);
exact_status packed_ideal(packed_layout, packed_address *, int include_highest);
exact_status packed_bad(packed_layout, const packed_address *, int *bad);
exact_status packed_correct(packed_layout, packed_address *);
typedef struct { uint64_t rank, destination, payload; } exceptional_record;
exact_status packed_sort_reinsert(exceptional_record *, size_t length,
                                  uint64_t *holes, size_t hole_count,
                                  uint64_t *payloads, stream_work *);
#endif
