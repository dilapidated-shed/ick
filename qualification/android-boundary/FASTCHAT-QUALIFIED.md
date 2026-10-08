# FastChat application qualification, 2026-10-07

The current repair retains Android nullability and availability metadata. This
follow-up also retains nullability on an array parameter's adjusted pointer;
it preserves static bounds and ordinary C pointer syntax. A typed constant null
argument diagnoses the retained _Nonnull annotation. Metadata does not become
an optimizer nonnull assumption.

Producer source: 9c6fd6ed5b202cdb1852319365e6097c454921e8 plus the owned array
and typed-null changes in this commit. Parent c2b84a381d23bf5d0b5153e24be51a52e78a022e
changes only the workflow relative to that source. Owned overlay SHA-256:
137d18f65b44629960403c200144a45e4dd1a02468df74357a169414d32191be.
Immutable GCC reference: 6294f1d9e7536e5ffcde09d1528c918d63abfef5.

Real host and ARM32 GCC builds completed. Focused expected-success/failure checks
are in focused-results.txt; the positive declaration executable ran with exit 0.
The API-21 unchanged NDK r29 Bionic file/NativeActivity header fixture compiled
with -Wall -Wextra -Werror. Object SHA-256:
e6c6697a845c9e2aad1632f25fcaaff2c186a3232a77effd32743f45a3afe0dc.
Readelf confirms ELF32 ARM v7, VFPv3-D16, no hard-float argument convention.
The fixture includes file, stat and timerfd declarations used by FastChat.
BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD is the explicit documented Bionic C overload
opt-out; no headers, declarations or annotations were stripped.

Compiler binary SHA-256:
- host xgcc: bab7d51e28a405827ff343fb7b9edfabb61690e41a247fa106128e69b0407f1c
- host cc1: 36c2da06cb8a949a7ed955cd61b1c87f078125eb295eff79fdf0c6b46b5db1ce
- ARM xgcc: aab240cbd4f1522a46453c06c6381af25d5c2bc4ac3ca76f9c8668bb7501dac3
- ARM cc1: 8783851356800c451798929b0cefea0dd53da2b8a3fbc77f0ba6c73efdd9e5ac

An initial ARM configure lacked the extracted binutils runtime library path.
Its assembler probes were invalid; those objects were discarded. A fresh cache
and reconfigure with the matching binutils runtime path recovered hidden-symbol
and AEABI support, then all ARM compiler objects were rebuilt before these gates.

Both FastChat C cores execute their deterministic storage/transport/fault/replay
tests on the host. Both complete NativeActivity C slices compile as ARM32 ICK
objects and link using NDK platform CRT, stubs, builtins archive and ld.lld.
The platform link is an explicit NDK boundary; Clang did not compile C source.
FastChat's Canvas/Paint bridge requires API 26; the API-21 header probe is a
separate compiler qualification and does not lower that application floor.

This is scoped application compilation evidence, not a full GCC test-suite run,
general C++ qualification or Android runtime acceptance. Exact application
revisions, APK receipts and comparison evidence belong to FastChat's drafts.
Physical MIRO A1 install, launch, presentation, IME and measurements:
**BLOCKED/NOT_RUN**. No build tools were installed on the phone.

