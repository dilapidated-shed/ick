# Certified Gaussian resampling

The scalar domain is the disk grid at p=101..256. Every trusted constant and
series value has two directed dyadic bounds with 64 guard bits. Products use
checked 32-bit limbs from the accepted MUL-1 representation, and every division
or discarded bit is explicitly directed. A 1024-bit private workspace is a
declared resource bound rather than arbitrary-precision acceptance.

The machine component belongs to the requested ICK C path. Its independent
reference is generated in pinned Idriç Integer/Chez, with separate series and
larger precision. No floating library routine, RefC compiler or generated C
oracle supplies trusted digits.

The intended types distinguish a disk-grid scalar, a directed real interval,
a scalar precision certificate, and an ordered line-map parameter certificate.
Fresh contexts own their interval buffers. Outputs and contexts must not alias;
failed public calls preserve valid output buffers. Inputs outside the admitted
precision, capacity or analytic hypotheses return explicit refusals.

MUL-1 is consumed at d050bb1c66c4162ea3f4406f774317ef039dc9ed. The author-hosted
Harvey–van der Hoeven reference PDF is pinned by SHA256
7acbf5bea9dd45a2fca79d8b4673df6b8329ba8ad039831a40b44ae70944f813. Recipes are
Lemmas 2.12–2.14 and 4.8–4.12. Ordered A and B0 retain their surrounding
permutations in the transform identity.

This is an implementation checkpoint. Scalar and line-map execution gates are
not yet accepted, and no dependent composition is admitted from it.

The scalar checkpoint now executes 141 cases at p=101,128,256 with the retained
ICK compiler. A separate Idriç reference uses Euler's positive arctangent series
for pi, sum 1/(n 2^n) for log 2, reciprocal positive exponentials with repeated
squaring, and four trigonometric doublings. It has 128 additional bits and does
not call the candidate's Machin, atanh, quarter-reduction or negative-series
routines. The independent gate verifies enclosing constants, disk membership,
strict two-grid-unit errors, the range-reduction inequalities, term certificates
and an explicit candidate import list. Both source sets compile with the exact
required compilers; the scalar comparison passes. Full ordered resampling,
required defects and dependent APIs are still pending.

The generated reference record needed public export for its constructor and
field projections; an export-only record could not be consumed by the separate
gate. This was corrected in Idriç, preserving its independent arithmetic path.
