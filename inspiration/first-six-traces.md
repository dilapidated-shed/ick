# First six construct traces

Source-archeology pass: 2026-09-29

This note traces the first six cases from
[`kernel-construct-corpus.md`](kernel-construct-corpus.md) through the pinned
compiler sources. It records implementation seams, not winners.

The reduced C inputs live in [`fixtures/`](fixtures/). They are independently
written from the stated semantics; no Linux-kernel source was copied into the
fixtures.

## Exact source pins

| compiler | source pin |
|---|---|
| ICK / GCC reference | `gcc-mirror/gcc@6294f1d9e7536e5ffcde09d1528c918d63abfef5` |
| Clang / LLVM | `llvm/llvm-project@d7daf1d24be8231f7f422ef2bca1003d4b77ec11` |
| TinyCC | `TinyCC/tinycc@9db1105c32afd3dcf0c28b8186f08e63c761b2b5` |
| chibicc | `rui314/chibicc@90d1f7f199cc55b13c7fdb5839d1409806633fdb` |
| cproc | `michaelforney/cproc@d1c53ddf56571573a7025324c8dd5c6d547a4d1f` |
| lacc | `larmel/lacc@30839843daaff9d87574b5854854c9ee4610cdcd` |
| 8cc | `rui314/8cc@b480958396f159d3794f0d4883172b21438a8597` |
| cparser | `libfirm/cparser@81330da3ee9650c88a1afdc93de654b9dfd9fb78` |
| libFirm used by that cparser pin | `libfirm/libfirm@9107be1e1035dae7e509fce6abdbd7a1e8a83565` |
| CompCert | `AbsInt/CompCert@66a9fd06ef88619cc94765ca995a1018f7259b5c` |
| PCC | `PortableCC/pcc@201554009decadafd2af7c7d1dd631e583967dd8` |
| slimcc | `fuhsnn/slimcc@9778925e26ec13ea97fb0cba611d6d0ed608be6a` |
| c4 | `rswier/c4@2feb8c0a142b2e513be69442c24af82dbaf41a25` |

## Important distinction: `inline` has two jobs

C gives `inline` language/linkage semantics. An optimizer may separately
replace a call with the callee body.

The sources make that distinction unusually visible:

- GCC records declared-inline state in its trees and has a real interprocedural
  inliner in `gcc/ipa-inline.cc`.
- Clang records inline/always-inline information in the AST and hands
  optimization to LLVM.
- libFirm has a real heuristic inliner in `ir/opt/opt_inline.c`.
- CompCert has a verified/defined optimization pass in
  `backend/Inlining.v`.
- TinyCC stores inline functions as token lists and emits them only if
  referenced. Its documentation describes this deferred emission; that is not
  call-site substitution.
- chibicc tracks `is_inline`, reachability, and referenced static-inline
  functions, but its README explicitly says it has no optimization pass.
- 8cc accepts `inline` and then ignores it in declaration-specifier parsing.
- slimcc explicitly says it currently does not inline functions.
- cproc records C11 "inline definition" semantics in `decl.c`/`cc.h`; no
  cproc inlining pass was found in the pinned source.
- lacc postpones unused inline-definition emission. The inspected source shows
  inline-definition bookkeeping but no separate body-substitution pass.
- PCC has explicit inline machinery in `cc/ccom/inline.c`, enabled through
  its inline optimization option.
- c4 has no `inline` keyword at all.

So a later executable test must measure both **emission/linkage semantics** and
**actual elimination of the call**.

---

# Case 1 — one-field wrapper struct

Fixture: `fixtures/01-wrapper-struct.c`

This mirrors ICK's `typedef struct { byte payload; } E4M3`-style types.

## GCC / ICK

- C parser: `gcc/c/c-parser.cc`,
  `c_parser_struct_or_union_specifier`.
- Generic layout: `gcc/stor-layout.cc`, `layout_type`.
- GCC then carries the aggregate through TREE/GIMPLE and later scalarization,
  ABI classification, and target lowering.

ICK currently inherits this entire path. Its low-precision wrapper design adds
semantics in headers and targeted GCC changes rather than replacing GCC's
ordinary record representation.

## Clang / LLVM

- C parser: `clang/lib/Parse/ParseDecl.cpp`,
  `Parser::ParseStructUnionBody`.
- AST record: `RecordDecl` / `FieldDecl`.
- Layout: `clang/lib/AST/RecordLayoutBuilder.cpp` and
  `ASTRecordLayout`.
- CodeGen lowers the semantic AST into LLVM IR; LLVM's optimizer can then
  scalar-replace or otherwise erase aggregate machinery.

The notable architecture difference from GCC is the deliberately exposed AST
record/layout layer, which other Clang tooling also consumes.

## TinyCC

- `tccgen.c:struct_decl` parses enum/struct/union declarations.
- `tccgen.c:type_size` computes compile-time size/alignment.
- The same compact compiler/codegen path then assigns ABI locations and emits
  target instructions.

The wrapper crosses far fewer named representations than in GCC/Clang.

## chibicc

- `parse.c:struct_union_decl`, `struct_decl`, `union_decl`.
- `Type` and `Member` are the visible semantic representation.
- README pipeline: tokenize -> preprocess -> typed AST -> direct x86-64
  assembly.

This makes the wrapper easy to follow end-to-end: no optimizer IR sits between
typed AST and assembly.

## cproc / QBE

- `decl.c:structdecl` constructs the C type.
- `cc.h` stores struct/union metadata and members.
- cproc lowers the expression/function to QBE IL in `qbe.c`.
- QBE then owns registerization and machine lowering.

This is the cleanest example in the set of keeping a C frontend while
delegating the backend through a small textual IR contract.

## lacc

- Type construction lives in `src/parser/typetree.c`.
- Parser routines build a control-flow graph directly rather than first
  building a complete syntax tree.
- The IR in `include/lacc/ir.h` uses three-address code in basic blocks.
- Backend is currently x86-64-specific.

For this case, lacc is interesting because the aggregate enters a CFG-oriented
IR while parsing is still in progress.

## 8cc

- `parse.c:read_rectype_def` handles struct/union definitions.
- `parse.c:update_struct_offset` computes structure layout.
- Parsed expressions become the small internal node representation and then
  direct x86-64 assembly.

## cparser / libFirm

- cparser represents compound types in `src/ast/type*.h`.
- size/layout accessors live in `src/ast/type.h` and related type code.
- `src/firm/ast2firm.c` maps C AST/types into libFirm graphs.
- libFirm then owns graph optimization and machine lowering.

The frontend/backend boundary is much more explicit than GCC's integrated
tree/GIMPLE/RTL lineage.

## CompCert

- Parser/elaboration creates C composite definitions.
- `cfrontend/Ctypes.v:sizeof_composite` defines composite sizing inside the
  formal C type semantics.
- The aggregate then passes through the verified C-to-Clight and later
  compilation transformations.

CompCert's unusual feature here is not a shorter path; the size/layout
operation itself participates in the semantic model used by proofs.

## PCC

- C grammar/front end: `cc/ccom/cgram.y` and the pass-1 type machinery.
- `cc/ccom/pftn.c:tsize` computes type sizes.
- Machine-independent pass 2 and `arch/` backends handle later lowering.

The old two-part retargetable shape remains visible in current PCC.

## slimcc

- `parse.c:struct_union_decl`, `struct_decl`, `union_decl`.
- chibicc ancestry remains visible, but slimcc adds substantially more
  code-generation optimization and compatibility machinery.
- Direct machine-code/assembly generation still keeps the pipeline far
  shorter than GCC/LLVM.

## c4

The pinned c4 language does not implement structs. This fixture should fail at
the language frontier; that failure is useful evidence rather than a defect in
the trace.

---

# Case 2 — `static inline` wrapper operation

Fixture: `fixtures/02-static-inline.c`

This mirrors the dominant style of `ick/imprecise.h`, `ick/circle.h`,
Wegert helpers, and Pauli's ICK complex boundary helpers.

## Real optimization inliners

- GCC: `gcc/ipa-inline.cc`.
- LLVM: optimizer inlining after Clang code generation.
- libFirm: `ir/opt/opt_inline.c:inline_functions`.
- CompCert: `backend/Inlining.v`.
- PCC: `cc/ccom/inline.c`.

## Primarily C inline semantics / deferred emission

- TinyCC: `VT_INLINE`; inline token bodies are stored and emitted at the end
  only if referenced.
- chibicc: `Obj.is_inline`, `mark_live`, and `is_live`; README says no
  optimization pass.
- cproc: `FUNCINLINE` and `decl.u.func.inlinedefn` implement C11 inline
  definition rules; no separate inliner was found.
- lacc: `symbol.inlined`, `inline_definitions`, and
  `pop_inline_function` manage definition emission; no separate call-site
  body-substitution pass was found.
- 8cc: declaration parsing accepts and ignores `inline`.
- slimcc: README explicitly states that it currently does not inline
  functions; `-ffake-always-inline` exists for compatibility.
- c4: no inline keyword.

This case should therefore report at least three outcomes:

1. accepted and linked correctly;
2. unused inline body omitted;
3. call actually substituted/eliminated.

A single "supports inline" column would hide the most interesting difference.

---

# Case 3 — union + designated initializer

Fixture: `fixtures/03-union-designated.c`

The fixture deliberately reads back the active union member. It tests union
layout and designated initialization without relying on cross-member type
punning or byte order. ICK's float/integer union punning remains a separate
ICK-specific track.

## GCC / ICK

- parser grammar and initializer-list parsing:
  `gcc/c/c-parser.cc`;
- initializer semantics and designator state:
  `gcc/c/c-typeck.cc:set_designator` and related initializer machinery;
- record/union layout: generic GCC layout machinery.

## Clang / LLVM

- syntax uses `DesignatedInitExpr`;
- `clang/lib/Sema/SemaInit.cpp:InitListChecker` builds the semantic
  initializer form;
- after semantic analysis, Clang explicitly rewrites designated initializers
  into their subobject positions and fills omitted subobjects with implicit
  initialization nodes.

That explicit syntactic-form -> semantic-form split is a strong idea to compare
against GCC's initializer machinery.

## TinyCC

- `tccgen.c:decl_designator`;
- `struct_decl` and `type_size` provide compound layout.

## chibicc

- `parse.c` has array/struct designator parsing;
- `union_initializer` explicitly chooses the first member by default and
  permits another member via a designator.

## cproc

- `init.c:designator` handles initializer designators;
- `decl.c:structdecl` and the `structunion` member list supply layout/type
  information.

## lacc

- initializer parsing is isolated under `src/parser/initializer.c`;
- type information comes from the parser type tree;
- the parser emits three-address IR as the initialized object is lowered.

## 8cc

- `parse.c:read_initializer_list`;
- `read_rectype_def`;
- designated state is carried explicitly into initializer-list parsing.

## cparser / libFirm

- `designator_t` is a first-class AST object;
- initializer traversal/checking keeps designators in the C AST;
- `ast2firm.c` lowers the checked form into Firm IR.

## CompCert

- parser-side form: `cparser/C.mli` has explicit
  `Init_struct` and `Init_union` constructors;
- initializer elaboration is preserved across parser passes;
- verified initializer translation lives in `cfrontend/Initializers.v`.

This is the strongest example of an initializer representation designed for
reasoning rather than immediate code emission.

## PCC

- grammar in `cc/ccom/cgram.y`;
- initializer-stack machinery in `cc/ccom/init.c`.

## slimcc

- `parse.c:initializer2` and the struct/union parsing routines;
- same broad direct-AST-to-codegen family as chibicc, with more compatibility
  work.

## c4

No struct/union support, so no designated aggregate initialization.

---

# Case 4 — compile-time layout assertion

Fixture: `fixtures/04-static-assert-layout.c`

This is directly analogous to ICK's assertions about byte width, Float16,
binary32, and complex-object storage.

## GCC / ICK

- `gcc/c/c-parser.cc:c_parser_static_assert_declaration*`;
- `sizeof` and aggregate layout use the normal TREE type/layout machinery;
- assertion expressions are constant-evaluated in the frontend.

## Clang / LLVM

- `ParseStaticAssertDeclaration` in the declaration parser;
- semantic constant evaluation produces a `StaticAssertDecl`;
- `ASTRecordLayout` supplies target-specific aggregate sizes/alignments.

## TinyCC

- token `TOK_STATIC_ASSERT`;
- `tccgen.c:do_Static_assert`;
- `type_size` supplies size/alignment.

## chibicc

No `_Static_assert` token or parser implementation was found in the pinned
source search. Do not convert that observation into a final compatibility
claim until the fixture is compiled; mark it **not found / test required**.

## cproc

- token `TSTATIC_ASSERT`;
- `decl.c` consumes the declaration and calls integer constant-expression
  evaluation;
- struct layout lives in the C type machinery.

## lacc

- token `STATIC_ASSERT`;
- `src/parser/declaration.c` parses the assertion;
- type sizing is supplied by the parser type system.

## 8cc

- `keyword.inc:KSTATIC_ASSERT`;
- dedicated `_Static_assert` handling in `parse.c`;
- structure layout comes from `update_struct_offset` /
  `update_union_offset`.

## cparser / libFirm

- parser token `T__Static_assert`;
- parser handles it in `src/parser/parser.c`;
- constant folding and target type size live in the AST/libFirm boundary.

## CompCert

- lexer/parser explicitly support `_Static_assert`;
- `cparser/Elab.ml:elab_static_assert` elaborates/checks it;
- composite size/layout is formally defined in `cfrontend/Ctypes.v`.

## PCC

- lexer recognizes `C_STATICASSERT`;
- grammar/front-end constant-expression machinery handles it;
- `tsize` supplies aggregate sizes.

## slimcc

The parser/type system contains the chibicc-derived aggregate machinery plus
newer-standard support. A dedicated compile run should establish the exact
static-assert path rather than relying on ancestry.

## c4

No static assertion and no struct layout.

---

# Case 5 — mask/shift extraction

Fixture: `fixtures/05-mask-shift.c`

This is the first case aimed directly at E3M2/E4M3/E5M2-style encoding.

## GCC / ICK

- C semantic checking creates `LSHIFT_EXPR` / `RSHIFT_EXPR` in
  `gcc/c/c-typeck.cc`;
- C folding occurs in `gcc/c/c-fold.cc` and generic folding;
- optimized GIMPLE passes can combine masks/shifts;
- optabs and target descriptions select final target operations.

The key question for ICK is how much of this machinery actually improves the
small fixed masks/shifts used by low-precision encodings.

## Clang / LLVM

- Clang AST uses `BinaryOperator` with `BO_Shl` / `BO_Shr`;
- CodeGen emits LLVM shift/bitwise IR;
- LLVM combines masks, shifts, demanded bits, and target patterns later.

This cleanly postpones target optimization until after source-language
semantics are finished.

## TinyCC

- shift tokens map directly to `TOK_SHL`, `TOK_SHR`, `TOK_SAR`;
- `gen_op` and target generator files lower them with a short path;
- the experimental IL generator also has explicit shift operations.

## chibicc

- AST kinds `ND_SHL` / `ND_SHR`;
- `type.c` assigns shift result types;
- constant evaluator handles constant shifts;
- `codegen.c` directly emits x86-64 `shl` / `shr` / `sar`.

This is the clearest "no optimizer middle layer" comparison against GCC.

## cproc / QBE

- C expression/type semantics stay in cproc;
- `qbe.c` emits QBE IL;
- QBE owns shift selection and later simplification.

## lacc

- `src/parser/expression.c:shift_expression`;
- `src/parser/eval.c` checks integer operands and emits the IR operation;
- `src/backend/x86_64/compile.c` handles immediate versus `%cl` shift
  encoding.

The semantic-to-machine path is easy to inspect because each level is explicit
and small.

## 8cc

- `Shl` / `Shr` node/operator tokens live in the compact parser/node
  machinery;
- direct x86-64 codegen follows, with no optimization pass.

## cparser / libFirm

- cparser lowers the checked AST to libFirm;
- pinned libFirm has first-class `iro_Shl`, `iro_Shr`, `iro_Shrs`;
- `ir/opt/iropt.c` contains algebraic shift/mask rewrites;
- target transforms such as `ir/be/ia32/ia32_transform.c` select final
  instructions/address modes.

This case makes libFirm's graph optimization concrete rather than abstract.

## CompCert

- shift operations survive into explicit target-independent/target selection
  operations such as `Oshl`, `Oshr`, `Oshru`;
- target files such as `x86/SelectOp.vp`, `aarch64/*`, and
  `riscV/*` define selection and register needs;
- semantics of those operations are themselves represented in Coq.

## PCC

- pass-1 optimizer `cc/ccom/optim.c` already rewrites some shift patterns;
- machine-independent pass 2 and target tables/backends finish selection.

The i86 TODO even calls out multiplication-by-constant becoming shifts, a
useful reminder that old small compilers also accumulated local algebraic
strength reductions.

## slimcc

- AST operations `ND_SHL`, `ND_SHR`, and arithmetic-shift distinction;
- `type.c` handles integer promotion/type rules;
- `codegen.c` contains basic codegen optimization before direct emission.

## c4

c4 supports `Shl` and `Shr` directly. This is the only one of the first
five cases that c4 can represent without extending its language subset, making
it a useful lower bound for the machinery needed to parse and execute shifts.

---

# Case 6 — explicit copy loop versus `memcpy`

Fixture: `fixtures/06-copy-loop-memcpy.c`

This case deliberately contains both a pointer/length loop and a `memcpy`
call. A guarded `__builtin_memcpy` variant lets us test compilers that expose
one.

## GCC / ICK

- `BUILT_IN_MEMCPY` is a first-class builtin;
- optimization passes reason about memcpy calls;
- `gcc/builtins.cc:expand_builtin_memcpy` and block-copy expansion choose
  inline operations versus libcalls/target mechanisms.

A later pass must separately locate and measure GCC's loop-to-memcpy idiom
recognition for this exact fixture; this source pass does not assume it fires.

## Clang / LLVM

- Clang `CGBuiltin.cpp` turns `memcpy` / `__builtin_memcpy` into an LLVM
  memcpy intrinsic;
- LLVM `LoopIdiomRecognize.cpp` explicitly counts and forms memcpy from
  suitable loop load/store patterns;
- `MemCpyOptimizer.cpp` transforms and removes memcpy-related operations;
- backend lowering chooses machine operations or a library call.

This is the strongest explicit loop -> semantic memory intrinsic -> target
pipeline in the set.

## TinyCC

- `__builtin_memcpy` exists, but the documentation says memory/string
  builtins are mapped to libc;
- ordinary `memcpy` therefore stays much closer to a call boundary than in
  GCC/LLVM.

This supplies a particularly clean comparison for compile speed versus
whole-program optimization ambition.

## chibicc

- no `__builtin_memcpy` implementation was found;
- ordinary calls are ordinary AST calls;
- no optimizer exists to recognize the explicit copy loop as memcpy.

## cproc / QBE

- no cproc `__builtin_memcpy` implementation was found;
- ordinary `memcpy` is a call lowered to QBE;
- the explicit loop reaches QBE as ordinary control flow/load/store
  operations.

Whether QBE later simplifies the exact loop requires a separate QBE-source
trace; do not attribute GCC/LLVM-style loop idiom recognition to cproc.

## lacc

- parser builtin machinery keeps a `decl_memcpy` reference specifically for
  code generation;
- the CFG/three-address IR represents explicit loop control flow;
- backend handling can choose copy operations/calls.

The existence of a dedicated memcpy declaration without GCC-sized builtin
infrastructure makes this path worth a closer follow-up.

## 8cc

No `__builtin_memcpy` implementation was found and no optimization pass
exists. An ordinary library call and explicit loop should therefore remain
structurally distinct unless codegen has a local special case.

## cparser / libFirm

- cparser registers `memcpy` among runtime functions in
  `src/firm/firm_opt.*`;
- libFirm represents block copies as `CopyB`;
- pinned `ir/lower/lower_copyb.c` lowers small copies to loads/stores and
  large copies to `memcpy`;
- target backends may keep/expand medium cases differently.

This is a very useful alternative design: one explicit block-copy IR node with
target-tunable lowering thresholds.

## CompCert

- memcpy is represented explicitly as `EF_memcpy(size, alignment)`;
- CSE models its memory effect;
- each backend has `Asmexpand.ml` handling for memcpy;
- register-clobber requirements are explicit in target `Machregs.v`.

That explicit size/alignment-bearing external-function representation is worth
comparing directly with GCC builtin metadata.

## PCC

- `cc/ccom/builtins.c` contains `__builtin_memcpy`;
- aggregate-copy paths on some targets construct memcpy calls;
- the machine-independent / target split decides later expansion.

## slimcc

- project scripts explicitly rewrite Linux `__builtin_memcpy` to `memcpy`
  for compatibility, strong evidence that the guarded builtin fixture should
  currently be expected to fail;
- the explicit copy loop goes through slimcc's ordinary AST/codegen path.

## c4

c4 has no `memcpy` builtin and its tiny language subset lacks much of the
declaration/type machinery in this fixture. A smaller c4-specific pointer loop
may be useful later as a conceptual lower bound, but changing this fixture to
fit c4 would weaken the cross-compiler test.

---

# What this first trace already says

## 1. GCC's cost is visibly layered

Even these six cases touch parser, TREE/type layout, constant folding, GIMPLE,
IPA, builtin expansion, optabs, and target machinery. The extra machinery is
not arbitrary: each layer buys specific analysis or retargeting capability.

The right ICK question is therefore not "how do we make GCC look like TCC?"
It is "which layer pays for itself on ICK's programs and targets?"

## 2. Clang's most interesting contrast is representational separation

For these cases Clang keeps a rich source AST and layout model, then crosses a
clear boundary into LLVM IR. Designated initialization especially shows this:
the AST retains written syntax while Sema constructs a separate semantic
initializer form.

That is an idea ICK can study without adopting LLVM.

## 3. libFirm's `CopyB` is unusually concrete inspiration

Small, medium, and large aggregate copies remain one explicit IR concept until
a target-aware lowering decision. This is more directly inspectable than a
general claim that "graph IR is cleaner."

## 4. Tiny compilers reveal which work is optional

chibicc/8cc/c4 make the negative space visible:

- no inliner;
- little or no optimizer;
- direct shifts;
- ordinary calls stay calls;
- unsupported language features stop at the parser.

That makes them useful controls when measuring what GCC machinery contributes.

## 5. CompCert reveals where semantics can remain explicit

Composite size, initializers, shifts, and memcpy effects all remain named in
formal intermediate representations. ICK does not need whole-compiler proof to
benefit from the same discipline on its own unusual transformations.

# Next executable pass

Compile each fixture with the compilers that claim the required source
features, preserving the source pin and exact flags.

For each successful compilation, capture:

- accepted/rejected and diagnostic;
- front-end or IR dump when supported;
- assembly/object output;
- whether a wrapper survives or scalarizes;
- whether the inline call survives;
- how a designated initializer appears after semantic lowering;
- the computed aggregate size;
- exact shift/mask instruction sequence;
- whether the loop becomes memcpy;
- whether memcpy becomes inline loads/stores or stays a call.

Do not compare runtime speed yet. First establish what transformation each
compiler actually performed.
