# MUL-1 exact arithmetic and independent oracle

The component domain is signed arbitrary-capacity integers divided by a power
of two, represented by checked 32-bit unsigned magnitude limbs. A Gaussian
value is a rectangular pair. Operations return explicit capacity, allocation,
or invalid-input failures and preserve the destination on failure. Distinct
records may not alias storage; the same record may be an input and output.
Serialization is exact fixed-width big-endian two's complement at an explicit
binary scale, with no implicit rounding.

The scalar network has h=6, twenty ordered triples, two hundred ordered
neighbors, six central values and one star. Its eight actual schedule steps
implement addition and their reverse implements subtraction. Three network
calls with exchanges implement the signed swap. All arbitrary auxiliary values
are restored. Allocation and intermediate overflow refuse transactionally.

The separate oracle uses Idriç `Integer` and direct incidence, never the
candidate's schedule. `Oracle.idr` emits the serialized component contract;
`Gate.idr` compares complete bytes and refuses unexpected dynamic imports,
including an oracle-bypass `system` call. These are compatibility `.idr` files
originally qualified with compiler 081b9cde0591154839fb5d80d76e5570e0436300, using its
Chez backend. No RefC or generated-C oracle is admitted.

The first generated source was lost before remote publication. This recovered
implementation requires fresh ICK execution and fresh oracle evidence. Historical
results are not current acceptance. Native Chez 10.4.1 failed at startup on this
container; its same pinned source in threaded portable mode is being qualified.
The host Scheme bootstrap and maintained ICK target compiler remain separate.

Original STAR scalar examples are exported alongside signed Gaussian, zero,
large-limb, basis, inverse and swap cases. The immutable whole-product corpus
is an input pin; it does not turn this scalar component into a whole multiplier.

Effects are limited to explicit allocation, contract-file output and test
process invocation. The desired design could express checked capacities and
nonaliasing in types; the pinned compiler presently checks those contracts at
runtime. The next language acceptance boundary is direct execution of the same
serialized contract through the native word/buffer backend in ARM-2.

## October 20 source repair and current owned oracle

Independent adverse callers exposed two metadata aliases omitted by the
limb-buffer guards. A comparison result could point to an input's sign field;
a serialization byte buffer could point to that same metadata. Both calls
returned success and overwrote the input. The new fixtures first fail with
`FAIL exact_compare output aliases input metadata` and exit 40. After repairing
only comparison, serialization independently fails with its own diagnostic and
exit 40. Both guards now reject overlap with the input record itself before
writing. The original limb-overlap, capacity and transactional controls remain.

The actual current owned Idriç compiler/API source
`2734ac5a86610eddfab73b1644d72b4ac85a65ee`, through Chez, compiles the unchanged
oracle, gate and outer runner. The oracle's 225,758 records retain SHA-256
`cf36c5767db82ba4abb4d18be3ea871f24b7b470d34bb08abb7710cf6b62d074`.
Workflow, dependency lock and version check now name that actual compiler and
its bootstrap prefix. No RefC or generated-C oracle is substituted.

A separately labelled local diagnostic replay used the declared C61 scalar
host compiler with its explicit `-fno-link-libatomic` flag. `make check mutants`
passed, matching the complete stream and rejecting all five defects through
the actual outer runner. The byte-matching oracle bypass still fails only on
its dynamic-import provenance. These local diagnostics do not replace the
required retained 143e29580 compiler/own-runtime qualification. The existing
hosted exact-source workflow must execute that profile with the repaired
candidate and current independent oracle before merge acceptance.
