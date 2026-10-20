# Bounded ICKY compiler source lane (K2)

`__builtin_icky(…)` selects maintained ICKY syntax explicitly. Configure exactly
one absolute provider with `-ficky-parser=/path/to/protocol-executable` or
`-ficky-parser-package=/path/to/qualified-native-package`. A missing, failed,
empty, malformed or mismatching parser cannot fall through to C expression
parsing. This reserved builtin is recognized even without a provider.

The admitted results are one ASCII name or digit-only C integer token, nested
parentheses around that noun, or `name ← noun`. The parser must return exactly
one expression with complete token coverage. Other ICKY glyphs and general C
expressions, declarations, strings, aliases and suffixed/hexadecimal literals
are outside this initial lane. GCC still performs lookup, assignment checks,
conversions, target representation and code generation. Written `010` retains
GCC's integer tree (eight); ICKY's decimal Nat ten checks spelling consistency
and is never the C value.

CPP token spellings are copied before ICK's existing Unicode operator lowering.
The immutable parser buffer joins those exact spellings with single spaces.
The consumer checks the entire V3 UTF-8 frame, character/line/column/byte
coordinates, every written token, nested structure, paths and ordered coverage.
It retains actual GCC spelling and macro-expansion locations, verifies spelling
slices against physical source snapshots, then checks those snapshots again
after the child exits. Harmless source comments/spacing and simple macro
expansion are supported through these maps. CPP's explicit line-directive flag
rejects `#line` and GNU linemarkers, including redirects to existing files with
matching token text. Preprocessed inputs containing such markers, unavailable
files and pasted/spliced tokens without a unique physical slice refuse. Raw files are
bounded to 1 MiB each / 8 MiB total; parsed buffers to 64 KiB / 512 tokens / 32
group levels; protocol output to 1 MiB.

`-ficky-receipt=FILE` appends producer-observed raw snapshots, exact parsed
buffer, spelling/expansion maps, selected argv and complete protocol as TSV
with hex-encoded byte fields. `syntax-accepted` means only this compiler checked
the syntax boundary. It does not certify semantic output or independent origin.
The hosted qualifier retains external execve observations and final program
hashes separately; these are HOST_OBSERVATION, not isolated authenticated
producer admission. BC-P01-S01's approved ICK role/witness interface is still
an upstream obligation: its retained observer currently assumes clang-18.
No replacement admission system is introduced here.

The hosted workflow builds the exact compiler on a disposable runner and uses
the original ICKY package from run 38344914067, artifact 11788713633, parser
source `bc2aad9006d3d44e896d2f5092a7ac82e7bf066b`, built by canonical Idriç
`2734ac5a86610eddfab73b1644d72b4ac85a65ee`. The complete inner tar SHA-256
is `e897b96dd7485af9eec79644e2f5db36bc12b8ff38251f39eb97a5e0778f7734`.
Changing or losing this artifact refuses qualification; it is never rebuilt
inside the consumer. The compiler invokes the package's declared native ELF /
Chez / application entrypoint directly with a fixed environment. Its separate
Grease replay harness is not substituted with another shell.

The test executable exercises the C++ foreign protocol boundary using output
from the real Idriç parser. Hosted positive programs assert C octal/decimal
semantics, names, groups, macros, comments and unchanged ordinary ICK syntax at
O0/O2. Compiler refusals exercise unavailable/no-op parsers, unsupported source,
neighboring glyph, fabricated maps, token paste and GCC's const assignment rule.
This is K2 producer qualification. K3 still owns independent object/ABI oracles,
unused-parser/wrong-result mutants and authenticated witness verification.
