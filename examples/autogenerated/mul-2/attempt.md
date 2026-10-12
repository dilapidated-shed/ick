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
