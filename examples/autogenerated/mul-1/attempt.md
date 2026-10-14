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
for the required compiler 081b9cde0591154839fb5d80d76e5570e0436300, using its
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
