# Reduced exact layers and synthetic convolution

This component consumes the immutable MUL-1 and MUL-2 interfaces listed in
`dependencies.lock`. `numerical.h` exposes the model, its descriptors, execution
receipts and explicit refusal boundary. It uses exact signed dyadics and Gaussian
pairs throughout. Floating values in the fixture measure CPU seconds only.

## The admitted layer

In the accepted 64-coordinate binary frame space, let each of four vectors be
the tensor of one first-axis coordinate vector with the distinguished triple
indicator on the other two axes. They have disjoint supports of weight nine.
Functions constant on their common orthogonal complement have sixteen Fourier
characters. Every frame operator is Fourier diagonal, so this space is closed.
The global C operator restricts to four tensor factors C: its eigenvalue is
`i^(9 weight(frequency)) = i^weight(frequency)`.

The distinguished X endpoint's tensor indicator is the sum of the first three
vectors. Its Z character stays in the admitted space. Other X endpoints need
characters outside it, so every X row except zero must vanish. Y and auxiliary
rows may contain arbitrary disk-grid values. Source/sink character corrections,
the `i^27` sink phase, physical exchange and inverse Y sign are explicit.
Unused coordinates are constant; C fixes constants. The selected D=1..4
coordinates therefore receive C tensor D, including nonzero auxiliary roles.
Applying S on both sides and `(1-i)^D/2^D` gives H0 tensor D.

Character encoding and decoding are exact changes of representation. The
complete accepted framed motif executes sixteen times between them; no ordinary
butterfly supplies the candidate layer. All 944 roles are reserved and padded
outputs are checked for zero. One grid truncation follows the completed layer.

Encoding uses at most four fractional bits. In a motif invocation the source
bank stays unchanged, so half edges add at most one fractional bit per stage.
Three stages and at most four factors `(1-i)/2` need at most eleven additional
fractional bits. An invocation's temporary component is below sixteen times
the incoming maximum; three stages, decoding and the unhalved b temporary
have absolute components below 2^18. The model reserves 32 fractional and
32 magnitude guard bits.
These bounds do not assert the published Delta or factor-two row reservation.

## Transform and product contracts

The descriptor admits r=2,4,8, up to four axes of lengths r or r/2, at least
one nontrivial axis, at most 64 records and precision p=2..256. The constructor
checks the caller's record budget against all persistent transform and layer
buffers. Named bits of equal significance are interleaved into K=1 chunks by
L; each degree-r polynomial suffix remains contiguous. DIF writes low frequency
bits into high original named slots, giving B. The forward result stays in LB
order. The opposite procedure consumes LB, applies inverse monomials before
layers, traverses the rounds backward and restores L only at the end.

Each layer batches independent planes into admitted Y/auxiliary rows with X
rows zero. The selected address set is complete. Signed monomial multiplication
rotates the suffix, negates the wrapped tail and applies the quotient sign.
Its exponent uses only that axis's current branch bit and unprocessed lower
named bits. One completed round has one Qp site; forward signed permutations
commute with truncation. Each exact round contracts the disk. At most ell
rounds give a strict error below `sqrt(2) ell 2^-p`.

The polynomial product packs signed grid numerators in base `2^(4p)` with
explicit carries. A named provider receives exactly four unsigned magnitude
pairs, ac/be/ae/bc. Its identity, calls and actual bit lengths are recorded.
Signed centered extraction checks the padded high coefficient and final sign
carry. Combining the Gaussian parts and folding coefficient j+r into j with
the opposite sign gives the raw negacyclic numerator. Division by r and final
Qp are explicit. The built-in schoolbook provider is admitted only for this
reduced model; disk validation products are counted separately.

Convolution checks both original operands against radius 1/2, executes two
retained-order forward transforms, the packed product at every stored record,
the opposite transform and the exact outer M scale. Its result is cyclic
convolution in the axes and negacyclic convolution in y, divided by rM. The
strict error is below `sqrt(2) M (3 ell+1) 2^-p`. The squared certificate is
reported with denominator `2^(2p)`; it must be strictly below 1/4 before the
call proceeds. The original radius and this error preserve the unit disk.
The final declared component width is `p+2+log2(M)`.

## Evidence and boundaries

The independent pinned Idriç reference uses exact tensor sums, direct ring DFTs
and quadratic Gaussian ring convolution. It verifies squared distances to the
direct transforms and convolution without candidate routines. Byte gates also
check every completed stage and all four provider receipts. Corpus hashes,
compiler identities, ELF properties, dynamic imports, raw standard streams,
candidate/gate/outer statuses and preparation/steady CPU and wall measurements
are retained under `build/numerical` by the qualification workflow.

Plans own mutable work buffers and permit one active call at a time. Input and
destination buffers must be independently initialized with the declared
capacities and alias rules. Value destinations remain unchanged on failure;
receipts may record completed work before a failure. Observers receive borrowed
snapshots and may abort a call before destination commit. Persistent buffer
counts are reported separately from observed whole-process Linux peak RSS.

Dense full-frame arrays, a saving recurrence, the h=100 schedule, published
row/header/Delta admission, an asymptotic short-product provider, native ARM,
Android and physical-device execution are outside this model's acceptance.
`numerical_published_admission` refuses that unsupported profile. The missing
published certificates are not inferred from these bounded executions.
