# Certified Gaussian resampling

The scalar domain is the disk grid at p=101..256. Every trusted constant and
series value has two directed dyadic bounds with 64 guard bits. Products use
checked 32-bit limbs from the accepted MUL-1 representation, and every division
or discarded bit is explicitly directed. A 1024-bit private workspace and
65,536 coefficient slots are declared resource bounds.

The machine component belongs to the requested ICK C path. Its independent
reference is generated in pinned Idriç Integer/Chez, with separate series and
128 extra bits. No floating library, RefC or generated-C oracle supplies digits.
The types distinguish disk-grid scalars, directed intervals, scalar precision
certificates, and ordered line-map parameter certificates. Fresh contexts and
plans own their buffers. Invalid capacities, aliases, hypotheses, disk/grid
values and nonzero padding refuse while preserving every valid output.

MUL-1 is consumed at d050bb1c66c4162ea3f4406f774317ef039dc9ed. The author-hosted
Harvey–van der Hoeven PDF is pinned by SHA256
7acbf5bea9dd45a2fca79d8b4673df6b8329ba8ad039831a40b44ae70944f813. Recipes are
Lemmas 2.12–2.14 and 4.8–4.12. Ordered A and B0 retain their surrounding
permutations in the transform identity; the old sorting wrapper is not used.

The complete local gate passes 8,090 records at profiles (p,s,t,alpha)
(101,12,17,4), (128,15,23,5) and (256,31,38,6). It checks enclosing constants,
disk membership, strict scalar and line error limits, actual range reductions,
all line basis directions, signed dense and half-grid values, upward nearest
ties, the retained Ps/Pt identity, and a 2x18x19x3 padded tensor box. Every
unused zero and tagged prefix/suffix field preserves its physical position.

The independent scalar reference uses Euler's positive arctangent series for
pi, sum 1/(n 2^n) for log 2, reciprocal positive exponentials with repeated
squaring, and four trigonometric doublings. Its line reference directly sums
wider Gaussian kernels and encloses a longer inverse matrix, checks the row
norm below one half and adds a geometric inverse remainder. It does not call
the candidate's Machin, atanh, quarter reduction, negative series or grid
products. The interval-record constructor and projections needed public export
to be consumed by a separate gate; that was corrected in Idriç.

A follows S/2 term by term. B0 follows D' times the finite alternating N^-1/2
recipe and the ordered C scan. The constructor checks all borrowed hypotheses.
Each plan charges coefficient buffers and reserved descriptors. CPU time for
constant construction, outer monotonic wall time, Linux peak RSS and exact
allocated bytes are retained separately. Counters are RAM work; the bounded
schoolbook products and series do not establish a multitape speed theorem.
CERTIFICATES.md records the error derivations and downstream scale obligations.

A normalized quadratic DFT supplies verification only, checking Ps Fs against
2^(2alpha^2) B0 Pt Ft A. Its explicitly amplified error bound is kept separate
from the unamplified contraction bounds. A/B0 do not invoke that transform.

All five prescribed defects fail through the real outer runner: one missing
Neumann term, reversed dilation, downward ties, a relaxed series tail, and zero
values. An additional executable bypasses arithmetic by copying the complete
normal candidate bytes through an external process. The gate rejects that
extra import even when every value matches: candidate=0, gate=9, outer=9 and
the matching-byte receipt are required. Raw stdout, stderr and every status
are retained.

The pinned parser required let expressions in comprehension heads to be
replaced by typed row functions. The first padded-reference attempt used the
reserved name prefix; it became prefix_index in Idriç. Iterations use finite
ranges. These corrections preserve the independent Idriç path. Helpers have
component-specific module names and job-specific TTC directories; Makefile
dependencies rebuild them when compiler commands change, addressing the stale
helper collision observed in the combined MUL-1/MUL-2 qualification.

This local qualification is a bounded numerical component. Exact-head hosted
verification is configured separately. Whole multiplication and physical
Android/device acceptance require their later independent gates.
