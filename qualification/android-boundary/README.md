# ICK Android leaf boundary

These fixtures exercise the narrow compiler boundary needed by Wegert:
compile a header-free leaf C translation unit with ICK, then let Android NDK
r29 Clang/lld perform the final API 21 shared-library link.

The compiler deliberately does not provide an Android sysroot or target
runtime libraries. Use it for `-S` or `-c`, not as the Android linker driver.

Floating `_Complex` values use ICK's physical polar representation.  Keep
every `_Complex` value and operation inside an ICK-compiled translation unit.
The boundary to NDK Clang/C++ must contain only ordinary scalar and pointer or
array parameters; the ICK `_Complex` calling and object ABI is not compatible
with Clang's Cartesian representation.

This draft is qualified only for the exercised leaf-object pattern.  The
focused suite covers direct returns of complex constants and lvalue stores
through `__real__` or `__imag__` on nonvolatile objects.  It also covers
compile-time conversion of semantic complex constants to complete physical
object bytes and of complete physical object images back to semantic
components.  Partial or volatile bytewise views of complex storage, and calls
to external functions that accept or return `_Complex`, still have
representation gaps.  The Wegert fixture uses none of those operations; they
remain blockers to treating this as a general maintained `_Complex`
implementation.

This qualification covers finite Cartesian inputs only.  ICK's two-word
polar representation does not preserve every ISO C `_Complex` distinction
involving infinities, NaNs, or signed-zero quadrants; code needing those cases
must handle them explicitly at the scalar boundary.

The original AArch64 receipt also verifies a relocated compiler and executes
focused polar-storage and radial floor/ceil tests under QEMU. The four-ABI
foundation workflow uses this same scalar boundary for `arm64-v8a`,
`armeabi-v7a`, `x86_64`, and `x86`. Its object/link gate does not qualify an
Android runtime execution, NDK headers, C++ interop, TLS, sanitizers, LTO,
long-double ABI details, arbitrary Android platform APIs, an APK, or F-Droid
packaging.

The load-alignment gate follows the Android platform boundary rather than
pretending every CPU has a 16 KiB runtime: `arm64-v8a` and `x86_64` require
16 KiB-compatible `PT_LOAD` segments, while the two 32-bit ABIs retain their
4 KiB requirement. [Android's NDK build-system guidance](https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md#page-sizes)
states that 16 KiB page-size devices are 64-bit and that there are no plans to
change the page size for the 32-bit ABIs.

The Actions artifact is short-lived qualification output.  A consumer should
use an immutable release archive and verify its published SHA-256 checksum.
