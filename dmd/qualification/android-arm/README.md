# Native Android ARM bring-up

This is an executable first slice, **not a complete Android D implementation**.
The compiler itself runs on the build host. D source passes through the owned
Icky DMD parser and semantic passes, including its Unicode source surface.

| Target | Production code-generation path |
| --- | --- |
| `armv7a-linux-androideabi21` (`thumbv7a` also accepted) | New typed-AST Thumb-2/VFPv3-D16 emitter, writing ARM ELF32 bytes directly |
| `aarch64-linux-android21` | Existing Mars AArch64 generator and ELF64 writer, with Android target wiring and scalar-leaf admission checks |

Neither path translates through C, invokes LDC/GDC, or invokes an assembler to
compile D. A bootstrap D compiler builds the owned compiler. Clang assembles
only the independent **test harness**; LLD links that harness with DMD's object.
There is no Java, Gradle, JNI, DEX, or NDK dependency in these freestanding tests.

## Qualified slice

Top-level `extern(C)` leaves with up to four scalar arguments: binary32 floats,
32-bit signed/unsigned integers, booleans, and pointers. Caller-owned float
buffers, loads/stores, local variables, arithmetic, comparisons, conditional
branches and loops are exercised. Thumb arguments/results use the base AAPCS
(softfp) register boundary; hardware VFP performs Float32 arithmetic internally.
AArch64 uses its distinct integer/pointer and FP argument register banks.

Thumb uses stack homes and caller-saved scratch registers, with a checked
504-byte maximum frame and an 8-byte-aligned stack. Its `-O` invocation is a
regression configuration, **not a claim of a Thumb optimization pass**. The
AArch64 `-O` invocation uses the existing native optimizer. Both Android forms
require `-betterC -c` and reject runtime/linking/debug/profiling modes.

Unsupported forms are errors, not omitted code. AArch64 now qualifies direct
top-level `extern(C)` calls whose return and at most four parameters stay
inside the already-qualified scalar set. The ELF gate verifies a
`R_AARCH64_CALL26` relocation with zero RELA addend, links it against an
independent definition, and executes the Float32 argument/result boundary.
Indirect calls and function values remain rejected.

Thumb now qualifies the same direct top-level `extern(C)` scalar-call
surface. The custom emitter evaluates arguments into stack homes, reloads the
softfp `r0-r3` boundary, preserves LR with an 8-byte-aligned stack, and emits
ordinary ELF32 `.rel.text` `R_ARM_THM_CALL` relocations. The independent
Thumb fixture resolves such a call against a separately assembled definition
and executes the Float32 argument/result ABI under QEMU.

Indirect calls and function values remain rejected on both ARM architectures.
Closures, allocation, exceptions, aggregates, global data,
binary64/extended-real representations and complete druntime/Phobos support
also remain outside this slice. Thumb additionally rejects integer division,
integer/float conversion, by-reference parameters, more than four argument
words, byte-element memory access, excessive frames and other unimplemented
expressions/statements. AArch64's guard remains deliberately conservative even
where the underlying native generator has additional capabilities. Its
unqualified extended-real ABI must not be exposed as Android `long double`
support.

## Reuse and corrections

The earlier `fuego-ironworks/idric-arm-thumb` `native-arm` emitter supplies the
softfp/stack-home design reference, not a second D parser or a copied runtime:
`src/Backend/ARMThumb/Emit.idr`, blob
`be9f6ed5e16e4e431574fe6146bb719b30e78b91`.

Mars already emitted AArch64 ELF before this change; it did not need replacing.
Execution tests exposed two real comparison errors in that path: integer
condition codes incorrectly treated unordered Float32 comparisons as ordered,
and a register-reuse operand swap was not reflected in floating-point compare
emission. The changes correct both. The direct-call gate later exposed a third
AArch64 object bug: `R_AARCH64_CALL26` RELA records incorrectly copied the BL
opcode `0x94000000` into the relocation addend. The instruction keeps the BL
opcode while the ordinary direct-call RELA addend is now zero. Android objects use ELF SYSV OSABI and
Bionic predefined identifiers; they do not inherit host Glibc identifiers.
The existing AArch64 register mask already excludes Android's reserved `x18`.

## Host and emulated execution

Install a host D compiler, C++ toolchain, Python 3, Clang, LLD, and QEMU user
emulators on the **build machine**, not the phone. Build the compiler:

```sh
repo=/absolute/path/to/ick
cd "$repo/dmd/compiler/src"
dmd -run ./build.d dmd HOST_DMD="$(command -v dmd)"
```

Then, from any working directory:

```sh
python3 "$repo/dmd/qualification/android-arm/verify.py" \
  --compiler "$repo/dmd/generated/linux/release/64/dmd" \
  --imports /absolute/path/to/matching/druntime/import \
  --output "$repo/build/android-arm"
```

Use `--qemu-arm` / `--qemu-aarch64` to override the default `qemu-arm-static`
and `qemu-aarch64-static` commands. CI pins the exact matching official DMD
bootstrap archive and rebuilds the compiler from the checked-out PR head.

Each architecture is executed both without and with `-O`: 840 input cases and
884 checked output words per configuration (3,360 case executions total).
The deterministic binary32 oracle covers calibration, clamping, weighted buffer
sums, in-place clipping and untouched tails, loops with break/continue, unsigned
dispatch, division, negation, and all six floating-point comparisons. It includes
signed zero, infinities, NaNs and subnormals. NaN payload equality is not required;
other results are compared bit-for-bit. Stack restoration and preserved registers
are checked; AArch64 checks `x18` as well. ELF class, machine, SYSV OSABI and Thumb
EABI flags are verified. Twenty-five negative tests cover target and admission
errors, including deletion of stale output after backend rejection.

`receipt.json` records compiler/source hashes, exact commands and outcomes.
**QEMU Linux-user PASS is not Android linker, Bionic, app-lifecycle or device PASS.**
The independent harness checks these leaf ABIs, not every possible D/C ABI form.

## Separate physical Android acceptance

The device runner builds position-independent probes with Android interpreter
paths and 16 KiB load alignment. It requires an explicit adb serial and checks
that the selected device advertises the requested ABI. It writes only into a
fresh random `/data/local/tmp/icky-dmd-arm-*` directory and removes that directory;
it installs no compiler, APK or library and changes no settings.

```sh
python3 "$repo/dmd/qualification/android-arm/device.py" \
  --serial DEVICE_SERIAL --architecture thumb2 \
  --compiler "$repo/dmd/generated/linux/release/64/dmd" \
  --imports /absolute/path/to/matching/druntime/import \
  --output "$repo/build/android-thumb-device"
```

Use `--architecture aarch64` for the other device/ABI. `--prepare-only` builds
probes without contacting a device and writes `PREPARED_NOT_EXECUTED`, never a
PASS. `device-receipt.json` is deliberately separate from emulation receipts.
Probe preparation has been tested; physical Android execution remains pending.
These are freestanding probes: passing them would still not qualify Bionic APIs,
JNI, an APK lifecycle, complete D runtime support, or DMD hosted on Android.

## Next implementation gates

1. Execute both exact-head PIE probes on physical Android, preserving binary
   hashes and independent device receipts; investigate rather than relabel any
   linker, ABI or runtime failure.
2. Extend Thumb lowering with explicit acceptance for additional scalar
   operations, byte accesses, calls/relocations and spilled arguments. Qualify
   aggregate/layout rules independently; remove admission limits only with tests.
3. Qualify matching druntime and Phobos on each Android architecture, including
   TLS, exceptions/unwinding, allocation and C interfaces. Host runtime PR #26 is
   not Android runtime evidence.
4. Compile and exercise an actual translated application and its required
   Android interfaces. Hosting DMD itself on ARM is a further, separate gate.

References: Android NDK ABI guide
<https://developer.android.com/ndk/guides/abis>; D predefined versions
<https://dlang.org/spec/version.html#predefined-versions>.
