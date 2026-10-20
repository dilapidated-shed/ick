#ifndef OPENAI2026_NETWORK_H
#define OPENAI2026_NETWORK_H
#include "exact.h"
#include <stdint.h>
enum { FRAME_DIMENSION = 64, FRAME_TRIPLES = 4 };
typedef enum { RATIONAL_LABELS, BINARY_LABELS } label_field;
typedef enum { DATA_X, DATA_Y, SIDE_ROLE, CENTER_ROLE } role_kind;
typedef struct {
  role_kind kind;
  unsigned identity, stage, coordinates[3], physical_x, physical_y, center;
} frame_role;
typedef struct {
  label_field field;
  int64_t entries[FRAME_DIMENSION][FRAME_DIMENSION];
} frame_matrix;
typedef struct {
  uint64_t vectors[FRAME_DIMENSION];
  unsigned length;
} binary_basis;
typedef struct {
  uint64_t rational_operations, matrix_entries, basis_operations, maximum_rational_bits;
} preparation_work;
typedef struct { int64_t numerator, denominator; } frame_fraction;
typedef struct {
  frame_fraction lower_first[64][64], lower_second[64][64];
  unsigned pivot_rows[64], pivot_columns[64], rank;
  uint64_t maximum_coefficient;
} frame_factorization;
exact_status frame_lower_factorization(const frame_matrix *, frame_factorization *, preparation_work *);
exact_status frame_check_factorization(const frame_matrix *, const frame_factorization *, preparation_work *);
exact_status frame_find_prime(const frame_factorization *, uint64_t search_limit, uint64_t *prime);
exact_status frame_apply_shear(const frame_matrix *, const frame_factorization *, uint64_t prime,
                               unsigned digits, uint64_t earlier[64], uint64_t later[64],
                               uint64_t *interchanges);
unsigned frame_role_count(label_field);
exact_status frame_role_at(label_field, unsigned identity, frame_role *);
exact_status frame_projection(label_field, const frame_role *, unsigned stage,
                              int time, frame_matrix *);
exact_status frame_difference(const frame_matrix *, const frame_matrix *, frame_matrix *);
exact_status frame_rational_rank(const frame_matrix *, unsigned *rank, preparation_work *);
exact_status frame_binary_basis(const frame_matrix *, binary_basis *, preparation_work *);
exact_status frame_check_binary_basis(const frame_matrix *, const binary_basis *);
unsigned frame_binary_phase(const frame_matrix *, uint64_t frequency);
uint64_t frame_tensor_indicator(const unsigned coordinates[3]);
unsigned frame_popcount(uint64_t);
unsigned frame_route_target(unsigned identity);
int frame_route_sign(role_kind);
exact_status frame_profile_admit(unsigned ground_dimension, label_field, uint64_t role_budget);
/* Exact one-column Fourier-character slice. Coefficients are Gaussian dyadics;
 * the physical 2^64-entry array is not materialized. Caller owns 944 records. */
typedef struct { uint64_t frequency; unsigned char phases[26][944]; } phase_character_schedule;
/* A prepared schedule is immutable while consumed. Its constructor is qualified
 * independently by the complete role operator oracle, not by scalar endpoints. */
exact_status frame_phase_prepare(uint64_t, phase_character_schedule *, preparation_work *);
exact_status frame_phase_network(exact_gaussian *, size_t roles, const phase_character_schedule *);
/* One-point finite-support slice; supplied physical source points must align
 * in a common gate frame. This coordinate executor counts RAM work. */
exact_status frame_bit_point_network(uint64_t *, size_t roles, uint64_t earlier[320][64],
                                     const uint64_t later[64], uint64_t prime, preparation_work *);
#endif
