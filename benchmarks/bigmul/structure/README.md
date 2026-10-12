# Scoped structure evidence

`check_mb18.py` re-executes and validates MB17 schoolbook traces before computing
weighted dependency depth, fan-in/out and layer sizes. Every read and result
carries its actual last-write dependency. This describes the executed logical
schoolbook dataflow; it does not describe lowered machine instruction dependencies.
Weights are stated in the receipt; zero-weight lifetime/movement events remain
distinct from arithmetic. Recursive/provider hooks need their own executed edges.

Permutation maps must be bijective. The checks retain the eight-point bit-reversal
cycle histogram, and exhibit two conjugate pair-swap maps with identical cycle
type but different logical index displacement. This displacement is a layout
statistic, not observed hardware locality. A small direct transform and its
independent radix-two factorization execute in Z/17Z, length four, root four,
with no normalization. These are controls, not paper-implementation traces.

The exact MB17 dependency is recorded in the branch ancestry; source identity is revalidated on each
run. Full recursive/paper/provider structure remains pending. No aesthetic score
or practical speed claim follows from these vectors.
