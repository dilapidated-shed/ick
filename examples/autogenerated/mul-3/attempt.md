# Exact layers and normalized synthetic convolution

Accepted dependencies are MUL-1 d050bb1c66c4162ea3f4406f774317ef039dc9ed and
MUL-2 3c404d610292faa0a7234f4a7ba23cb2ae76de3e, both qualified with exact-head
CI. The shared STAR corpus and manuscript pins remain immutable. Machine
components use the qualified retained ICK compiler; independent references use
pinned Idriç Integer/Chez. No floating or whole-input oracle path is admitted.

The packed-product domain is a disk-grid Gaussian polynomial of power-of-two
length 2..8 at precision 2..256. Signed coefficients become carry-corrected
base-2^(4p) fields. A named conventional provider is permitted only for this
reduced model. It receives four pairs of unsigned evaluation magnitudes and
records identities and actual operand/result lengths. Signs are restored before
centered coefficient extraction. Padded high coefficients and final sign/carry
are checked, then real/imaginary combination, negacyclic folding and fg/r
normalization are explicit. Disk validation products are counted separately.

The desired type sketch distinguishes signed coefficient streams, packed
evaluation magnitudes, the four-product provider receipt, a centered extraction
certificate, ordered transform shapes, completed-layer grids, and exact
intermediate Gaussian dyadics. Capacity and aliasing are runtime contracts of
the pinned substrate; public failures preserve valid destinations.

Phase/layer admission must consume the actual accepted role/frame schedule.
The existing h=4 interface qualifies finite-support and Fourier-character
slices; it does not qualify a dense 2^64-entry array or the published recurrence.
Any additional reduced invariant representation must be derived and checked
against the same operators, including every auxiliary and spectator. Ordinary
butterflies cannot silently replace the requested motif path. Published calls
must refuse unmet row, precision, schedule and short-provider conditions.

The packed checkpoint executes 1,824 raw-numerator, provider and rounded-output
records. A separate Idriç quadratic Gaussian convolution and direct Integer
evaluation oracle matches all bytes at p=2,3,5,9,33,101,256 and r=2,4,8 where
r<2^p. Cases include unit-disk boundaries, both signs, imaginary products,
half-grid inputs, mixed values, top coefficients and negacyclic wraps. Reference
SHA256 is 3ea051b8a930379bee1c1b14c2b678c69ce936dad432f3ace0be80054223a11b.
The compiler required a typed contribution function instead of a let expression
in a comprehension head; the correction remains in Idriç.

This is a partial implementation checkpoint. Complete phase/layer, transform,
convolution and required defect gates are pending. No MUL-5/ARM-2 dependency is
admitted from this branch yet.
