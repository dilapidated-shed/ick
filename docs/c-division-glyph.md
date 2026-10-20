# Icky C division

Icky C recognizes U+00F7 DIVISION SIGN (`÷`) as C's existing division token,
after preprocessing. It has the same precedence and left associativity as
`/`, and therefore the same precedence as `×`. Integer division still
truncates toward zero, floating division and the usual arithmetic conversions
retain their C semantics, and division by zero is not made safe or redefined.

Owned mathematical expressions use `÷` rather than an ASCII slash. This
is a **source convention**, not a new arithmetic type or an enforced ban on
ordinary `/`: foreign C and compiler substrate remain accepted. Pointer
declarations and dereferences retain `*`; member access retains `->`.
The literal glyph is not added to C++ or Objective-C.

The token is lowered only after preprocessing. Macro expansion can supply it;
strings, macro stringification and preprocessed text preserve the UTF-8 glyph
rather than silently substituting `/`. The regression exercises arithmetic
precedence and associativity, signed integer and floating division, macro
operand evaluation, pointer syntax, literal bytes and retained ordinary slash.
A separate negative test rejects U+2215 DIVISION SLASH (`∕`), rather than
treating visually similar Unicode operators as equivalent.

The Android foundation matrix compiles the positive test with the newly
built ICK across its four ABI configurations. Compiling is not an Android
runtime or physical-device qualification. Native execution, full ICK runtime,
and cross-architecture execution must be reported separately.
