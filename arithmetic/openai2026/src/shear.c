#include "layout.h"
#include "exact_internal.h"

static uint64_t add_modulo(uint64_t left, uint64_t right, uint64_t modulus) {
  return left>=modulus-right ? left-(modulus-right) : left+right;
}
static uint64_t subtract_modulo(uint64_t left, uint64_t right, uint64_t modulus) {
  return left>=right ? left-right : modulus-(right-left);
}
exact_status layout_interchange(uint64_t *earlier, uint64_t *later, size_t dimension,
                                uint64_t modulus, stream_work *work) {
  if (!earlier || !later || !work || !modulus || dimension>SIZE_MAX/sizeof(uint64_t)
      || exact_overlap(earlier,dimension*sizeof(uint64_t),later,dimension*sizeof(uint64_t))) return EXACT_INVALID;
  for (size_t coordinate=0;coordinate<dimension;++coordinate)
    if (earlier[coordinate]>=modulus || later[coordinate]>=modulus) return EXACT_INVALID;
  for (size_t coordinate=0;coordinate<dimension;++coordinate) {
    later[coordinate]=subtract_modulo(later[coordinate],earlier[coordinate],modulus);
    earlier[coordinate]=add_modulo(earlier[coordinate],later[coordinate],modulus);
    later[coordinate]=subtract_modulo(earlier[coordinate],later[coordinate],modulus);
    work->ram_operations+=3;
  }
  return EXACT_OK;
}
