# Sun F03 type and execution sketch

Base: IDK branch of `dilapidated-shed/ick`,
`45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0`.

This task changes a representation of the existing IDK D scalar, whose
executable source is `dmd/library/icky/imprecise.d`. It does not introduce an
Idriç source-language primitive or alter the unsigned UE5M3 byte codec.

Domain: 512 logical signed E5M3 codes in two-byte containers. The alternate
container has zero low seven bits. Code construction masks to nine bits;
raw storage admission rejects any nonzero low bits and preserves its output.
Widen: LeftE5M3 → Float16, preserving payload bits including NaN payloads.
Narrow: Float16 → LeftE5M3, RNE, with canonical positive NaN as specified.
Add/sub: LeftE5M3 × LeftE5M3 → LeftE5M3, calling the established exact-dyadic
operators. Explicit multiply pipeline: widen both, established Float16
multiply, narrow. Direct E5M3 multiplication remains rejected.
Comparisons are experiment predicates tested against decoded numeric values;
they do not add comparison operators to the production scalar.

Effects: only the qualification/benchmark entrypoints perform output, clocks,
and array allocation. Numerical functions have no allocation or I/O effects.

No Python, Node, generated C, or RefC substitute is used. D is selected because
the owned IDK scalar and qualification lane use D. ARM/Thumb inspection must
be labelled separately from host execution and from Idriç-generated code.

Execution results and remaining capabilities are recorded in the design note.

First blocked Idriç capability: a qualified ARM/Thumb handoff for this signed
nine-bit scalar. The inspected ARM branch still admits unsigned Ootomo E5M3;
the signed implementation lives on the IDK D line. No `.idric` source program
or source-level ARM acceptance is claimed. The next bounded language/backend
change must admit the signed scalar without redefining UE5M3 and emit both
representation followers. Its acceptance must run the same 512-code and
262144-pair suite on generated target code before timing either layout.
