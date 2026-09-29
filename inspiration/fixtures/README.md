# Executable reductions

These files are **secondary compiler probes** for the paired source archaeology
in [`../first-six-traces.md`](../first-six-traces.md).

They are not the source of the six cases. The source cases come from exact
Linux-kernel and ICK/Wegert/Pauli sites.

Mapping:

1. `01-wrapper-struct.c` — kernel `atomic_t` vs ICK one-field semantic
   wrappers.
2. `02-static-inline.c` — kernel `is_write_sealed` vs ICK `rotate96`.
3. `03-union-designated.c` — C-SKY pointer-view union vs ICK float/integer
   bit-view union.
4. `04-static-assert-layout.c` — kernel MD5 size/offset contracts vs ICK
   storage/complex-slot contracts.
5. `05-mask-shift.c` — kernel `FIELD_GET` surface/core vs ICK FP8/Circle96
   masks and shifts.
6. `06-copy-loop-memcpy.c` — kernel copy implementation vs Wegert ordinary
   memcpy calls vs Pauli/ICK builtin/object-representation copy.

A reduction should remain small enough to expose compiler stages, but it must
preserve the compiler question raised by the production source.
