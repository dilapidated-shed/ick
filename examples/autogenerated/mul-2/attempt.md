# Framed scalar networks and address layouts

The preparation domain consists of exact rational and binary subspaces of
three tensor factors, role/source/gate/sink descriptions, orthogonal residual
bases and explicit physical slots. The scalar-value domain stays separate:
bits for rational shear frames, Gaussian dyadics for binary phase frames.
An edge changes an address frame on one role. A common gate frame acts on
every incidence. Every routed role, including each auxiliary, receives its
specified endpoint correction.

The executable preparation profile is h=4, dimension 64. Its rational form is
I−J/9; h=9 is singular and must refuse. Binary residuals require actual checked
orthonormal bases. The published h=100 profile receives symbolic counts and
certificates, with an explicit refusal to materialize its enormous role set.
Reduced profiles do not inherit the published rank saving.

`network_generator.idr` uses Integer to produce the independent symbolic
contract and reduced role/edge expectations. Candidate preparation uses checked
exact rational elimination and binary basis construction. Corpus and source
identities are immutable. No candidate result is read by the oracle.

Required operations include deterministic elimination, projection/rank checks,
prime exclusion, address split/merge and counter order, three elementary shears,
eight packed shifts, exceptional-address extraction/correction, stable sorting
and reinsertion. All work, bit growth and cache storage are charged explicitly.
Resource, singularity, certificate and capacity failures are explicit values.

The input MUL-1 component is accepted at
c53800d945392f74b5e88a5661940c62dfac06b6 with 225,758 exact records and all required
defect/provenance gates. The generator targets pinned Idriç
081b9cde0591154839fb5d80d76e5570e0436300 through Chez. No alternate-language oracle
or approximate arithmetic is introduced.

The implemented reduced interfaces are a finite-support one-point bit array
and one-column Fourier-character Gaussian arrays. The first executes all 320
basis directions in five parallel bit planes, applies the actual rational
edge permutations modulo 223, checks physical gate alignment, and preserves
the later address fields. The second executes all 944 role basis directions
and five dense signed complex cases through the actual three-stage gates and
frame phases. These exact restricted representations avoid materializing a
2^64-entry array; they are not dense-array or tape-cost acceptance.

The frame reference contains 10,931 records, including 8,368 edge certificates,
all 1,264 routed endpoints, complete restricted role operators, and physical
bit addresses. Packed tests compare 123,904 direct maps and execute a closed
4,096-record bad-address orbit with nonzero payloads through correction,
stable LSD sorting and reinsertion. Sorting uses two sequential bucket tapes;
RAM checks are distinguished from modeled tape moves. Full packed rectangles
with active correction remain too large for this profile.

All five required defects propagate nonzero statuses through LayoutRun.idr; their
actual stdout, stderr, candidate, gate and outer statuses are retained. LayoutGate.idr
compares the whole reference and an explicit dynamic-import allowlist.

Pinned Idriç exposed several source errors during generation: numeric lists
needed explicit Integer types; conditional expressions in comprehensions
needed parentheses; a variable named guard shadowed the monadic guard; and
List.index' accepts a bounded Fin rather than an optional numeric index.
The sources were corrected in Idriç and no other-language oracle was used.
The discarded attempts and their failures remain described here. Generated
process code uses the existing escaped System seam, with an explicit fixed
stderr redirection so negative evidence survives the outer runner.

Hosted qualification first ran MUL-1 and MUL-2 in one checkout and exposed a
module-cache collision: both helpers were originally named Gate and Run.
The pinned compiler reused MUL-1's Run.ttc and invoked its older argument
contract. The layout helpers now have unique LayoutGate/LayoutRun module and
file names, job-specific TTC cache directories, and Makefile dependencies that
rebuild helpers when their compiler command changes. The combined qualification
sequence is required locally too; it also catches historical stale caches.

## BACKLOG-REPAIR-02 accepted-parent reconciliation

The scalar source is now accepted on main at bff5a413d2c86b85246017f16a8fbc76900e6942. The normal two-parent reconciliation a95112e4459371c2f3816e024d42a02f66cd979c preserves the independent frame/layout additions and main's newer compiler/runtime controls. The only textual conflict was the shared arithmetic workflow. Both scalar and layout positive/negative stages remain; both use the actual hidden-root Idriç/Chez 2734ac5 paths and the retained 143e29580 native ICK runtime profile. The Makefile inherits the accepted metadata-alias guards, oracle revision and unchanged scalar reference hash. The accepted_mul_1 lock now points to the actual main merge.

The target is main after its parent was integrated. Earlier green runs are historical and do not qualify this reconciled head. Exact-head inherited scalar, frame/layout and all required defects must run afresh. No ARM, physical A1/C67, whole-multiplier or paper running-time acceptance follows from these bounded profiles.
