# Icky C multiplication

The C frontend recognizes U+00D7 MULTIPLICATION SIGN (`×`) as C's existing
multiplication token after preprocessing. Arithmetic precedence, associativity,
conversions and side effects are unchanged. Macro expansion can supply it;
stringification, literal bytes and preprocessed output retain the glyph.

Owned mathematical expressions use `×`. Pointer declarations and dereferences
retain `*`, and member access retains `->`. This is a source convention:
the lexer maps the glyph to the existing token rather than introducing a new
type or enforcing a pointer-spelling rule. Ordinary foreign C remains accepted.
C++ and Objective-C do not gain the spelling.

The executable regression covers integer/floating multiplication, precedence,
left association, one evaluation of a macro operand, literal/stringification
bytes and ordinary pointer syntax. A targeted neighboring-glyph fixture must
be rejected. Both belong to the checksummed owned compiler overlay.

Native x86_64 compilation and execution were performed with the rebuilt ICK
frontend over GCC `6294f1d9e7536e5ffcde09d1528c918d63abfef5`,
using `-std=c11 -O2 -Wall -Wextra -Werror`. The native link used the Ubuntu
24.04 glibc/GCC 13 runtime objects and `-fno-link-libatomic`; no stock compiler
compiled the regression. This does not qualify a new ICK native runtime,
binary128 complex lowering, an Android ABI, or a physical device.

The existing Android foundation matrix compiles the positive fixture with its
freshly built ICK. Runtime results remain separately scoped.

