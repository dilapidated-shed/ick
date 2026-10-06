# A1 application C qualification — 2026-10-06

Repository classification: **OUT OF SCOPE / NO DEFECT FOUND** for mathematical
application structure. ICK itself owns the concrete compiler compatibility gaps
and the new regression fixtures below.

Application qualification is **ICK BLOCKED**, distinct from the successful
freestanding ABI boundary. No complete application is declared Icky.

The executed compiler was source-built from ICK
`79eccb8ff232e05bdbb9e345fc224f251636b43f`, materializing its pinned GCC reference
`6294f1d9e7536e5ffcde09d1528c918d63abfef5`. It reports GCC 17.0.0 20260813.
Local driver SHA-256: `72fdd5f3b8ad5d1b4edf11ad6d598bb18100160d55b21fa16fb994565517f1f0`.
System GCC/G++ built the compiler; GNU ARM binutils assembled its emitted code.
Neither bootstrap tool compiled consumer application C.

| Stage | Executed owner / result |
|---|---|
| C frontend | ICK/GCC, target `arm-linux-gnueabi` |
| Android declarations | NDK r27c / 27.2.12479018, Bionic unified headers and ARM include directory |
| Application settings | `-marm -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16`, `__ANDROID__`, application's API floor |
| Assembler | GNU `arm-linux-gnueabi-as` 2.42 |
| Object inspection | NDK LLVM readelf |
| APK packaging / signing / physical acceptance | Not executed by this qualifier |

`a1-application-abi.c` compiles: ELF32 EM_ARM, 32-bit pointers, A32 `$a`
mapping symbols, no `$t` code, base PCS rather than VFP argument PCS, 8-byte
double and required stack alignment. Thumb and hardfp mutations fail.
The real Fourier polynomial leaf and Wegert root-expansion leaf also compiled
through this command as A32 objects. This proves two leaves, not the programs.

Application probes were actually attempted for Young Tableaux (API 26), Flower
(24), Crystal (21), Wegert (26), and Fourier Voice (26). Every probe fails at
Bionic declarations. Minimal fixtures isolate both missing frontend features:

* `bionic-nullability.c`: `_Nonnull` / `_Nullable` are not parsed as qualifiers.
* `bionic-availability.c`: `availability(android, introduced=26, strict)` is
  not supported; `introduced` and `strict` produce undeclared-identifier errors.
* `bionic-headers.c`: reproduces those failures with real stdint/string/native
  activity headers. This is not a missing include path: both unified and ABI
  include paths are explicit.

Erasing all attributes, pretending to be Clang, or dropping API-availability
checks would change the contract and is not a repair. Current NDK compilation
remains an explicit separate lane while these features are unsupported.
The compatibility finding is executed against r27c; other NDK revisions and
non-A1 architectures are not newly qualified by this receipt.

`compile-application.grease` is the maintained shared compilation/inspection
step for this boundary. It requires a GCC ARM driver, writes compiler identity,
logs, and ABI evidence, and exits nonzero on compilation failure. It invokes
no replacement compiler. It is diagnostic evidence, not authentication of a
compiler release; the existing AICI producer still owns release admission.

`test-application-contract.grease` executed through real Grease. It rejects
Clang offered as ICK, rejects wrong ARM modes, and uses a compiling failure
fixture to prove that failed compilation produces no object and no successful
receipt. It reports header probes as `ICK_BLOCKED`, separately from the passing
contract tests. A future compiler must turn the feature probes into support,
then qualify every consumer translation unit and link/runtime boundary before
the full application can be called Icky.
