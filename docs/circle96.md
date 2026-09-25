# Circle96 machine geometry

ICK mirrors the concrete finite-circle semantics in Idriç PR #118.

A `Circle96` has 96 positions per turn. It is deliberately distinct from a
`Rotation96`, a `Reflection96`, and the signed local `Tangent96`
displacement.

```text
Circle96      point on the finite circle
Rotation96    orientation-preserving displacement
Reflection96  orientation-reversing symmetry
Tangent96     shortest signed local displacement
```

All four currently occupy one byte.

## Canonical codes

Circle, rotation, and reflection codes are canonical only in the range 0..95.
The 7-bit representation therefore has this useful sector interpretation:

```text
00xxxxx   first third
01xxxxx   second third
10xxxxx   third third
11xxxxx   spare
```

So:

```text
0    =   0 degrees
32   = 120 degrees
64   = 240 degrees
16   =  60 degrees
```

The low five bits give the position within a third.

## Operations

The public interface uses geometric operations rather than pretending the
values are ordinary integers:

```text
rotate96
compose_rotations96
inverse_rotation96
reflect96
local_displacement96
```

The named cam rotations are exact:

```text
one flat        16 ticks
half flat        8 ticks
quarter flat     4 ticks
eighth flat      2 ticks
sixteenth flat   1 tick
```

At the exact half-turn ambiguity, local displacement chooses -48.

Ordinary C addition on `Circle96` is rejected, and a `Circle96` cannot be
returned where a `Rotation96` is required. Integer instructions may implement
these operations after lowering, but they do not erase the source distinction.

This is the concrete `Circle 96` specialization of the broader finite-circle
machine model recorded in Idriç PR #118.
