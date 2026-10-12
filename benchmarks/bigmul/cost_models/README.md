# Scoped accounting controls

The named bounded binary-tape copy model explicitly charges descriptor preparation,
head travel, source scanning and destination writing. A single eight-bit control
register is assumed in the executed controls. Larger word widths imply a different
finite machine; they are not free registers on one uniform fixed-tape model.
Scalar charges are symbolic width-sized charges, not simulated multiplication.
Unknown operations refuse accounting instead of receiving zero cost.

Two small schedules copy the same value with identical logical RAM operations and
traffic but different tape movement charges. Exact hand counts and independently
executed finite values validate the difference. These tiny schedules do not
establish the paper's bounds. Transpose/permutation/network component accounting
awaits accepted MUL1..4 schedule contracts and remains NOT_RUN.

Executed schoolbook trace totals report logical reads/writes/bytes separately from
observed process-endpoint timings. Formatting, lowering and physical memory traffic
remain unresolved. No measured cache misses, simulation-based hardware claim,
candidate tape bound or practical speedup is inferred.
