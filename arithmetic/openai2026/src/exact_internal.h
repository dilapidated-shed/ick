#ifndef OPENAI2026_EXACT_INTERNAL_H
#define OPENAI2026_EXACT_INTERNAL_H
#include "exact.h"
int exact_valid(const exact_dyadic *);
int exact_overlap(const void *, size_t, const void *, size_t);
int exact_alias_invalid(const exact_dyadic *, const exact_dyadic *);
void exact_normalize(exact_dyadic *);
size_t exact_bits(const exact_dyadic *);
exact_status exact_magnitude_shift(exact_dyadic *, const exact_dyadic *, size_t);
#endif
