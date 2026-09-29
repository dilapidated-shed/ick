# Public discussion notes: alternative C compilers vs GCC

Research pass: 2026-09-29

Purpose: collect public discussion before deciding what, if anything, ICK should
learn from other C compilers. These notes deliberately separate reported
tradeoffs from ICK design decisions.

ICK remains GCC-derived. A source being interesting does not imply that its
code should be copied. Any later code borrowing needs separate provenance and
license review.

## Reading rule

For each compiler, ask the same questions:

1. What problem does it solve differently from GCC?
2. What does the smaller/different architecture buy?
3. What capability does GCC buy with its complexity?
4. Which comparison is about compiler implementation, which about generated
   code, and which about ecosystem/compatibility?
5. Which claims come from maintainers, which from users, and which from
   benchmarks whose methodology needs checking?

A recurring warning in compiler discussions is that benchmarks are unusually
easy to misread. Compile time, compiler memory use, executable size, generated
code speed, and standards/extension coverage are different measurements.

---

## Clang / LLVM

### Sources

- Clang project, "Features and Goals":
  https://clang.llvm.org/features.html
- Historical Clang comparison page, "Clang vs GCC":
  https://accserv.lepp.cornell.edu/svn/packages/root/interpreter/llvm/src/tools/clang/www/comparison.html
- LLVM developer discussion of GCC/LLVM performance and benchmark methodology:
  https://discourse.llvm.org/t/the-performance-of-llvm-vs-gcc/21268
- Historical LLVM developer SPEC comparison:
  https://discourse.llvm.org/t/tot-clang-llvm-and-tot-gcc-performance-comparision/17798
- A large GCC/Clang generated-code benchmark set:
  https://www.phoronix.com/review/gcc-clang-2019

### Notes

Clang is the clearest deliberate alternative to GCC in this set. Its own goals
name fast compilation, low memory use, expressive diagnostics, GCC
compatibility, a library-based architecture, and a code base intended to be
hackable. The historical comparison page explicitly contrasts this with GCC's
broader language/target support and accumulated extensions.

The architectural contrast matters more than a simple speed contest. Clang was
built as a reusable library and tooling substrate. GCC historically centered
the compiler executable and its internal pass machinery. Clang therefore made
AST access, source locations, refactoring/static-analysis clients, and IDE
integration first-class design concerns.

GCC's complexity buys real things: more languages, more targets, decades of
target tuning, many extensions, and mature optimization. Public performance
threads show no permanent "winner"; particular versions, targets, options, and
benchmarks change the result.

The LLVM developer performance thread is especially useful as a warning for
ICK. Participants point out examples where supposed compiler comparisons
actually compared different OpenMP support or even unoptimized code. Any ICK
benchmark suite should record flags, runtime libraries, target tuning,
available language features, and whether a test is really measuring the same
program.

### Questions for ICK

- Can GCC internals be exposed through smaller, stable library-like seams
  without rebuilding ICK around LLVM?
- Which Clang diagnostic/source-location ideas can be reproduced on top of
  GCC-derived parsing?
- Can ICK measure front-end cost separately from optimization and codegen cost?
- Do not infer that "Clang is simpler" means "LLVM as a whole is small."

---

## TinyCC (TCC)

### Sources

- TinyCC developer mailing-list thread explicitly asking "difference between
  gcc & tcc":
  https://lists.nongnu.org/archive/html/tinycc-devel/2005-03/msg00020.html
- Public "Tiny C versus gcc" discussion:
  https://comp.lang.c.narkive.com/0M5I0FSt/tiny-c-versus-gcc
- Hacker News discussion of tiny/self-hosting compilers and TCC as a middle
  point between tiny teaching compilers and GCC/LLVM:
  https://news.ycombinator.com/item?id=8576068
- Discussion around hand-optimizing TCC's code generator:
  https://news.ycombinator.com/item?id=30941097

### Notes

TCC makes the trade particularly stark: minimize compiler latency and machinery
rather than chase GCC's optimization depth. The old TinyCC mailing-list answer
frames TCC as dramatically faster to compile while GCC can produce much faster
code when aggressive optimization and target-specific options matter.

TCC also collapses boundaries GCC normally leaves to separate programs or
interfaces: compiler, assembler/linker behavior, in-memory compilation, and
`libtcc` make "compile C right now and call it" a normal use case. Public
discussion repeatedly treats this as the reason to use TCC, not as an attempt
to beat GCC at peak generated-code performance.

The useful idea for ICK is not "remove optimization." It is that compiler
latency is itself a product feature and can justify a deliberately different
path through the compiler. TCC shows the value of a very short path from source
to executable code.

### Questions for ICK

- Could ICK provide an explicitly fast, low-optimization path rather than make
  every invocation pay for the full GCC machinery?
- Which assembler/linker or in-memory compilation boundaries are small enough
  to expose cleanly?
- Could a fast path serve Android/device iteration while a slower path remains
  available for optimized release builds?

---

## chibicc

### Sources

- chibicc README:
  https://github.com/rui314/chibicc
- Hacker News discussion with Rui Ueyama explaining the pedagogical,
  commit-by-commit structure:
  https://news.ycombinator.com/item?id=33581704

### Notes

chibicc does not really compete with GCC as a production optimizer. It is
valuable precisely because it removes most of what makes GCC difficult to
learn. Rui describes the repository as a reference implementation for teaching
C compiler construction, with commits ordered so a reader can watch one
language feature appear at a time.

The README openly says it has no optimization pass and generated code can be
roughly twice or more slower than GCC. That is useful comparative evidence:
readability and incremental comprehensibility were chosen over generated-code
quality.

chibicc also shows that "small compiler" does not have to mean "toy grammar."
It implements a surprisingly broad set of C11 features and some GCC
extensions. The simplification lives primarily in architecture, target scope,
and optimization, not merely in deleting the hard parts of parsing C.

### Questions for ICK

- Can ICK document selected GCC mechanisms in a chibicc-like incremental
  sequence even though the implementation remains GCC-derived?
- Could small "start reading here" slices explain one feature end-to-end:
  token -> tree -> lowering -> target instruction?
- Which ICK extensions deserve minimal standalone examples rather than forcing
  readers through all GCC infrastructure?

---

## cproc + QBE

### Sources

- QBE Hacker News discussion including direct cproc/QBE vs GCC experience:
  https://news.ycombinator.com/item?id=40346320
- More recent QBE discussion mentioning cproc and reported GCC-relative
  generated-code performance:
  https://news.ycombinator.com/item?id=48059633
- Broader C compiler history discussion mentioning cproc as a modern small
  compiler:
  https://news.ycombinator.com/item?id=39367150

### Notes

cproc's most interesting contrast with GCC is decomposition. It delegates the
middle/back-end problem to QBE, which intentionally offers fewer optimizations
and a much smaller interface than LLVM or GCC. Public users report generated
code in the rough neighborhood of a substantial fraction of GCC -O2
performance while valuing the dramatically smaller code base. Treat those
numbers as anecdotal workload-specific measurements, not general benchmarks.

The architectural proposition is important: a C frontend does not have to own
a GCC-sized optimizer and backend to produce useful native code. QBE defines a
smaller optimization contract and accepts leaving some performance on the
table.

### Questions for ICK

- Can an ICK mode lower a useful subset into a much smaller IR/back-end seam?
- Which GCC passes produce most of the value for ICK's actual workloads?
- Could measurement identify a "small optimization budget" rather than
  inheriting every GCC pass by default?

---

## lacc

### Sources

- lacc project README and its explicit gcc/clang/tcc measurements:
  https://github.com/larmel/lacc

### Notes

lacc is unusually useful because its README publishes both compiler-cost and
codegen-quality comparisons. In its SQLite compilation test, lacc reports
dramatically fewer cycles, allocations, and allocated bytes than GCC, while
also reporting larger object output and inefficient generated code.

That cleanly separates two axes GCC often wins only after paying a large
compiler-resource bill: optimization quality versus compiler work. lacc's
author explicitly treats instruction selection/codegen quality as unfinished
work rather than pretending the compile-speed result settles the comparison.

For ICK this is probably one of the most useful measurement models in the
whole set: compiler cycles, compiler instructions, allocation count, bytes
allocated, output size, and runtime quality should be recorded separately.

### Questions for ICK

- Add allocation count/bytes and compiler instruction count to ICK
  qualification, not only wall-clock compile time.
- Measure how much individual GCC passes cost versus what they improve.
- Treat output object size as a first-class result on small Android targets.

---

## 8cc

### Sources

- 8cc README:
  https://github.com/rui314/8cc
- 8cc Hacker News discussion:
  https://news.ycombinator.com/item?id=9125912
- Rui Ueyama's implementation diary:
  https://www.sigbus.info/how-i-wrote-a-self-hosting-c-compiler-in-40-days

### Notes

8cc, chibicc's predecessor, explicitly chose small and readable source over
optimization and portability. Its README says generated code is commonly
roughly twice or more slower than GCC and warns users not to expect a mature
general-purpose compiler.

The HN discussion exposes implementation choices made primarily to reduce
compiler complexity. One notable example is arena/process-lifetime allocation:
the compiler simply does not free many allocations because compiler processes
are short-lived. That removes ownership bookkeeping and some bug classes at
the price of memory growth during a compilation.

This is a useful contrast with GCC because it asks which general software
engineering rules are actually useful inside a short-lived compiler process.
GCC must handle very large translation units and a huge feature set, so the
same choice cannot simply be imported; but the question is worth asking
subsystem by subsystem.

### Questions for ICK

- Audit allocations by lifetime. Which objects can safely share one
  compilation arena?
- Does ICK/GCC spend complexity recovering individual allocations that all die
  at process exit anyway?
- Can diagnostic/debug builds retain strict lifetime checking while fast builds
  use simpler arenas?

---

## cparser + libFirm

### Sources

- cparser README:
  https://github.com/libfirm/cparser/
- LLVM developer discussion of libFirm, including interest in its ideas and a
  warning that compiler ideas do not transplant mechanically:
  https://lists.llvm.org/pipermail/llvm-dev/2008-December/018729.html
- Public libFirm/cparser optimizer discussion:
  https://www.reddit.com/r/ProgrammingLanguages/comments/1e8qwis
- Historical GCC/LLVM/libFirm benchmark discussion:
  https://davmac.wordpress.com/2010/07/11/updated-c-compiler-benchmarks-llvm-2-7-libfirm-1-18-1/

### Notes

cparser separates a fairly conventional C frontend from libFirm's graph-based
IR, optimizer, and code generator. Its README explicitly aims to function as a
drop-in gcc/clang replacement in many cases.

The old LLVM developer thread is especially relevant to an "inspiration"
branch. Chris Lattner's response is effectively the right posture for ICK:
libFirm contains interesting ideas, but copying compiler code is both
architecturally nontrivial and license-sensitive. Study the idea first.

The more recent user discussion suggests libFirm remains interesting as an IR
even where its optimizer does not match modern GCC. Again, the comparison
splits representation quality from optimization investment.

### Questions for ICK

- Study Firm's graph representation separately from its benchmark results.
- Identify GCC structures whose difficulty comes from representation rather
  than necessary C semantics.
- Record any idea before code: what invariant does the representation make
  easier to express or verify?

---

## CompCert

### Sources

- Current CompCert manual:
  https://compcert.org/man/manual001.html
- CompCert project overview:
  https://compcert.org/compcert-C.html
- Original published CompCert performance/correctness discussion:
  https://www.cs.utexas.edu/~bornholt/courses/cs345h-24sp/papers/compcert.pdf
- Cornell discussion of the verified compiler and its performance tradeoff:
  https://www.cs.cornell.edu/courses/cs6120/2022sp/blog/compcert/

### Notes

CompCert changes the objective function. GCC primarily tries to compile a huge
language/ecosystem surface into excellent code over many machines. CompCert
treats semantic preservation as the central deliverable and accepts weaker
optimization.

Current CompCert documentation reports generated code around GCC -O1 territory
on its cited ARM measurements, not GCC's highest optimization levels. The
important comparison is not that CompCert "loses performance"; it buys a
machine-checked argument that verified compiler transformations preserve
program behavior.

For ICK, CompCert is the strongest reminder that optimization passes can carry
proof obligations or at least machine-checkable invariants. ICK does not become
verified by copying CompCert architecture, but individual numeric or geometry
transformations could have much tighter executable specifications and
equivalence tests.

### Questions for ICK

- Which ICK-specific transformations are small enough to specify independently
  and differential-test against a reference semantics?
- Can low-precision arithmetic lowering carry explicit before/after invariants?
- Where can property tests or translation validation buy confidence without
  attempting whole-compiler formal verification?

---

## Portable C Compiler (PCC)

### Sources

- Current PCC repository:
  https://github.com/PortableCC/pcc
- Public portability discussion comparing PCC, GCC RTL, and LLVM:
  https://www.thecodingforums.com/threads/most-portable-compiler-llvl-llc-or-pcc-or-gcc-rtl.953191/
- Historical discussion of PCC's attempted revival as a GCC alternative:
  https://www.phoronix.com/forums/forum/software/programming-compilers/31253-pcc-portable-c-compiler-isn-t-quick-to-advance
- Historical Clang page comparing Clang with PCC:
  https://android.googlesource.com/platform/external/clang_35a/+/19098dcde2b7597ad620b1d7bfe180dd69308648/www/comparison.html

### Notes

PCC's enduring attraction is retargetability and comprehensibility. The current
project describes a small machine-independent middle layer plus explicit
machine-dependent backends. Public discussion around its revival repeatedly
connects PCC with the desire for a compiler smaller and easier to retarget than
GCC.

The counterexample matters just as much: modern GCC/Clang ecosystems moved
faster on standards, extensions, targets, optimization, and real-world package
compatibility. A clean target interface is not enough by itself to replace the
accumulated engineering in GCC.

PCC therefore offers ICK a useful historical question: what was genuinely
valuable about old retargetable compiler structure, and what only looked
simple because old C, ABIs, optimizers, and target requirements were smaller?

### Questions for ICK

- Compare one PCC backend with the corresponding GCC backend structurally.
- Identify target description data that GCC spreads across mechanisms but PCC
  keeps visibly machine-specific.
- Preserve GCC capability while looking for places where target bring-up can
  be made more local.

---

## slimcc

### Sources

- slimcc README:
  https://github.com/fuhsnn/slimcc
- Recent Hacker News discussion on independent C implementations, slimcc, GCC
  compatibility assumptions, and portability bugs:
  https://news.ycombinator.com/item?id=47811154

### Notes

slimcc starts from chibicc but pushes toward real software: newer C standards,
GNU extensions, lower memory use, basic codegen optimization, and the ability
to compile substantial userlands. Its author makes an argument that is
different from both TCC and GCC: independent implementations are useful
because they expose software that accidentally depends on GCC/Clang quirks.

That makes compiler diversity itself a testing tool. A program that only ever
sees GCC and Clang may silently encode assumptions shared by those dominant
implementations.

For ICK this is especially relevant because ICK is GCC-derived. ICK cannot use
itself as an independent check on GCC semantics. Keeping genuinely independent
compilers in the inspiration set gives a useful external differential oracle.

### Questions for ICK

- Add portable-C corpus builds under independent compilers where practical.
- When ICK and GCC agree, do not treat agreement alone as proof if both share
  implementation ancestry.
- Use slimcc/TCC/cproc/Clang disagreements to locate assumptions worth
  specifying explicitly.

---

## c4

### Sources

- Hacker News discussion, "C4: C in Four Functions":
  https://news.ycombinator.com/item?id=22353532
- Thorsten Ball's public walk-through:
  https://registerspill.thorstenball.com/p/exploring-the-c4-compiler
- Public discussion treating c4 as a starting point for understanding and
  retargeting small compilers:
  https://forums.raspberrypi.com/viewtopic.php?t=336627

### Notes

c4 is not a GCC competitor in any ordinary production sense. It is useful as a
lower bound on how little machinery is needed to demonstrate the essential
pipeline. Public explanations reduce it to lexer, expression parser,
statement/code generator, and VM loop. It intentionally accepts a small C
subset and targets a tiny abstract machine rather than solving native
optimization, system headers, ABI breadth, or modern language compatibility.

The contrast with GCC therefore answers a different question: which compiler
concepts remain after almost everything concerned with production quality is
removed?

For ICK, c4 should not inspire compression or obscurity. Its useful role is as
a conceptual checksum: if an ICK subsystem cannot be explained in terms of a
small pipeline, identify exactly which production requirement adds the extra
machinery.

### Questions for ICK

- Write a tiny end-to-end model of an ICK compilation beside the real one.
- Name each extra layer and the requirement that justifies it.
- Avoid mistaking line-count minimalism for maintainability; c4 discussions
  themselves disagree sharply about readability.

---

# Cross-compiler themes to investigate next

## 1. GCC complexity is not one thing

Public discussions repeatedly bundle several independent costs under "GCC is
big":

- broad C/GNU compatibility;
- other source languages;
- many target architectures and ABIs;
- decades of optimization passes;
- target-specific tuning;
- compiler framework/generalization;
- diagnostics and debug information;
- driver/linker/system integration;
- backwards compatibility.

ICK should measure or inspect these separately. Removing one does not imply
removing the others.

## 2. Small compilers repeatedly trade peak code quality for compiler simplicity

TCC, chibicc, 8cc, lacc, cproc/QBE, PCC, and c4 occupy different points on
this curve. This suggests an ICK question more precise than "can GCC be
smaller?":

> How much compiler machinery buys how much measurable benefit on ICK's actual
> programs and targets?

That can be measured.

## 3. Frontend simplicity and backend simplicity are separate

chibicc/8cc simplify both. cproc keeps a real C frontend while delegating to
QBE. cparser delegates to libFirm. Clang has a sophisticated frontend but
makes it reusable as a library. CompCert invests heavily in intermediate
representations because proofs depend on them.

ICK should compare these layers independently.

## 4. Retargetability keeps reappearing

PCC, TCC, QBE/cproc, tiny-compiler discussions, and GCC itself all raise the
cost of adding a machine. "Number of supported targets" and "difficulty of
adding one more target" are different metrics.

This matters directly for ICK's ARM/Thumb and GPU work.

## 5. Independent compilers provide evidence that GCC descendants cannot

slimcc's strongest argument is ecosystem testing through independent
implementation. Since ICK inherits GCC source, GCC-vs-ICK differential testing
has correlated failure modes. Tests against Clang, TCC, cproc, slimcc, and
CompCert can expose different assumptions.

## 6. The most useful immediate benchmark may be compiler cost, not generated-code speed

lacc's published measurements suggest a practical ICK experiment:

- wall time;
- CPU cycles;
- retired instructions;
- peak RSS;
- allocation count;
- bytes allocated;
- object size;
- final executable size;
- generated-program runtime;
- generated-program code size.

Run the same corpus through GCC/ICK and the inspiration compilers that can
accept it. Only then decide which complexity is expensive and which earns its
keep.

# Next research pass

The next pass should move from discussion to source archaeology:

1. Pick one representative feature, such as integer addition, function calls,
   or a simple loop.
2. Trace it end-to-end through GCC/ICK, Clang, TCC, chibicc, cproc/QBE, lacc,
   cparser/libFirm, CompCert, PCC, slimcc, and c4.
3. Record number and kind of intermediate representations, allocation/lifetime
   strategy, optimization stages, and target-specific seams.
4. Keep code copying out of scope. The result should be an architecture map
   with source pointers.

That would turn public opinion into something inspectable.
