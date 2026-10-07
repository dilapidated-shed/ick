# Icky C assignment

ICK C accepts U+2190 LEFTWARDS ARROW (`←`) wherever C accepts the `=`
assignment/initializer token:

```c
struct AppendAddress *address_pointer ← &address;
address_pointer->offset ← written_extent;
```

The C frontend maps the exact UTF-8 token to its existing assignment token
after preprocessing. C's assignment precedence, right associativity, result,
type checks, lvalue checks, and side effects apply unchanged. Initializers,
designated initializers, enum values, and macro-expanded assignment also use
the same token. Ordinary `=` remains available for foreign C source.

The preprocessor preserves the glyph. String and character literals,
comments, macro stringification, and preprocessed output retain their normal
meaning and bytes. C++ and Objective-C are outside this change. This does not
introduce value-first `→` assignment or another arrow alphabet.

The complete changed frontend file belongs to `ick/source/gcc/c-family/`;
the immutable GCC reference stays unchanged. `ick/OVERLAY.sha256` covers both
the source and four GCC DejaGnu fixtures. Once materialized, the standard
GCC testsuite selector is `dg.exp=ick-assignment-arrow*.c`. The positive
fixture is executable, and the other three require rejection of read-only
assignment, a non-lvalue destination, and an unsupported neighboring glyph.

The existing Android foundation matrix compiles the positive fixture with
its freshly built ICK, without delegating C compilation to Clang. That is
compile evidence only; runtime evidence is recorded separately in
`qualification/c-assignment-arrow/`.
