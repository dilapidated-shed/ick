# Executed trace format v1

The TSV trace binds source, binary, exact ordered input-limb case, profile,
completeness and coordinate space. Events have sequential IDs, explicit units,
widths and references to prior events. Values describe executed schoolbook
reads, writes, multiply-accumulates, carries, results and buffer lifetimes.
Coordinates are logical limb indices. They do not describe observed addresses,
cache misses or an FFT, and the source does not introduce a compiler IR.

The control is bounded to 16 limbs per operand, so complete output is bounded.
Every 64-bit intermediate, 32-bit store/carry, input, output and operation count
is validated independently. Trace-enabled output is compared to the existing
uninstrumented C harness and Python integers. Output/formatting failure returns
nonzero. Dropped events, incomplete traces and mismatched executable identities
are refused. A trace identity is a binding receipt, not proof of binary semantics.

`check_mb17.py` emits raw traces and separate process-endpoint timings for the
traced and plain controls. Startup and formatting enter both distributions;
the difference is not claimed as pure observer overhead or multiplication time.
The retained recursive control is not established here. Future recursive,
transform/precision/provider events require a versioned schema extension and
executed provider hooks. Paper traces wait for MB16; these control traces cannot
be renamed to a paper profile. MB17's full recursive/provider scope remains
partial until those sources are qualified.
