# K2 compiler consumption: type and ownership sketch

Outcome: actual ICK C compilation consumes the retained Idriç ICKY parser's
version-3 tree. `__builtin_icky(target ← numeral)` is an explicitly selected
source lane; plain names/numerals and nested noun parentheses are also admitted.
Other ICKY grammar remains unsupported here. General C outside the lane keeps
its existing frontend.

The maintained Idriç producer is `dilapidated-shed/icky` at
`bc2aad9006d3d44e896d2f5092a7ac82e7bf066b`. Its actual archived native program
has been invoked with `--identity-v3`; outer/inner archive digests match the
independently qualified package. No duplicate Idriç grammar is introduced.

Domains: immutable preprocessed UTF-8 bytes; character/byte half-open intervals;
compiler-owned CPP token identities, source snapshots and spelling/expansion
locations; versioned located expression/group/name/natural/glyph nodes; GCC
typed expressions. A natural's ICKY decimal value and its C value are distinct:
written `010` binds parser decimal 10 to GCC's existing integer constant 8.

Central operations:

- capture : CPP token -> (written bytes, GCC value, spelling/expansion mapping)
- validate : immutable bytes -> CPP bindings -> V3 stream -> Either refusal tree
- lower : admitted tree -> GCC binding/type/assignment operations -> typed expression

Invariants: full source-frame equality; strict UTF-8 and all eight coordinates;
complete ordered token coverage; exact paths/group intervals/written slices;
decimal-spelling consistency; no unsupported grammar fallback. Locations must
resolve to retained real source bytes; fabricated `#line`, token-paste or other
ambiguous mappings refuse. Raw snapshots are checked again after parser exit.

Effects: a bounded private input file, direct child execution of the declared
native parser ABI, exit/output checking, optional compiler-owned TSV receipt.
Acquisition and independent package acceptance remain outside the compiler.
The package's native loader/Scheme/app entrypoint is declared separately from
its Grease launch harness; the compiler calls that unchanged native entrypoint.
The older Grease harness artifact locator is unavailable and is not replaced
with stock YSH or Bash.

Foreign boundary: GCC's existing C++ frontend owns CPP tokens, line maps, trees,
lookup, conversions and assignment. The small C++ consumer validates the Idriç
protocol and feeds those existing operations. It is not a replacement parser,
an Idriç-to-C fallback, or a new managed C++ runtime. All new syntax parsing is
performed by the retained compiled Idriç program. Tests at this foreign ABI use
the same consumer code and real compiler fixtures.

Execution status: IMPLEMENTATION_IN_PROGRESS. No compiler-backed or independent
K3 acceptance is claimed yet. Full GCC builds use the declared disposable hosted
build profile; this session lacks Flex and has less than 1 GiB free, so it is
not used as a full compiler-build host.

Language work: the current versioned Idriç protocol supplies the needed syntax,
positions and raw spelling. A direct typed Idriç/GCC AST foreign interface is
not implemented; this task exercises the maintained versioned process boundary.
