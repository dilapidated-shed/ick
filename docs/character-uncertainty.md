# Character uncertainty

Status: ICK design note, 2026-10-06. This extends the repository's work on semantic types with compact representations, but character uncertainty is not numeric rounding and should not be forced into the numeric imprecise-type machinery.

## Companion notes

- [Econometrician in a Box](https://github.com/bl4ckb4ll/econometrician/blob/main/notes/character-uncertainty.md)
- [Idriç](https://github.com/isomorphisms/Idric/blob/Idriç/_/character-uncertainty.md)
- [ARM Thumb](https://github.com/fuego-ironworks/idric-arm-thumb/blob/main/_/character-uncertainty.md)

## Semantic boundary

ICK should eventually provide a C/compiler-facing representation for uncertain character data while preserving the distinction between:

- visual/glyph proximity;
- physical keyboard/touch proximity;
- calibrated empirical confusion.

For example, lowercase `b p q d` can be close in a visual relation, while a broad QWERTY neighborhood around `D`

```text
W E R
S D F
Z X C
```

is close in an input-geometry relation. These are different facts even if both affect the same observed character.

## Do not make the lexer fuzzy by default

An uncertainty type is ordinary program data unless a future language feature explicitly opts into uncertain-source processing. ICK must not silently accept or rewrite identifiers, keywords, or source characters merely because they are near another character.

## C-facing shape to explore

A future freestanding interface should keep distinct fields or structures for:

- character identity;
- evidence channel;
- candidate hypothesis;
- cost/rank versus calibrated probability;
- context/provenance handle.

The exact ABI is deliberately unsettled. In particular:

- do not assume one byte per character;
- do not encode an uncalibrated distance as a probability;
- do not discard the evidence channel to save a tag byte;
- do not make one storage layout part of the source-level meaning.

A small-ASCII specialization may be useful, but it must be named as such and coexist with a general character path.

## Compiler/lowering experiments

ICK is a good place to compare representations produced from the same semantic fixture:

1. sparse candidate arrays;
2. bounded bitsets for explicitly bounded alphabets;
3. key-coordinate representations with generated neighbors;
4. fixed-point or integer costs with declared scale;
5. table-driven calibrated confusion models.

Measure code/data size and generated ARM behavior separately from semantic correctness.

## Shared fixtures

The first cross-project fixtures should include:

- observed `d` + visual evidence → close family `{b,d,p,q}`;
- observed `d` + QWERTY physical evidence → the eight surrounding positions above;
- a combined record that retains both evidence sources;
- a refusal to call arbitrary neighbor weights probabilities;
- a round trip through the C representation that preserves tagged evidence.

Econometrician in a Box owns statistical calibration; Idriç owns language semantics; ARM Thumb owns compact low-level target work; ICK owns C/compiler-facing representation and lowering experiments.
