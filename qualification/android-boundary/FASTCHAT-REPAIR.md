# Android metadata repair for FastChat

This source resumes the existing A1 qualification experiment. No compiler or
consumer merge is requested. The C assignment spelling is the owned lexer/test
from assignment fix 14f582c920af18ec20eb5fad2583926e0560b3f5; this branch does
not require that fix to merge.

The earlier pointer parser consumed nullability without retaining it. This
repair stores annotations on pointer types, supports pointer typedefs including
function returns, rejects conflicting annotations, and warns about constant-null
arguments/assignments to _Nonnull. It deliberately adds no optimizer nonnull
assumption. It is metadata plus constant diagnostics, not general flow analysis.

Availability fields are preserved and validated as named metadata. Calls and
address-taking are checked against an explicit numeric Android minimum API;
simple numeric macro aliases are resolved. A newer-API inline definition may
refer to APIs allowed by its own introduction annotation, while invoking that
inline from an older minimum still fails. Unknown/duplicate fields fail closed.
Unrelated GNU postfix function-definition attributes remain subject to GCC's
existing rejection. Runtime weak availability guards are not implemented here.

Bionic's documented BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD disables only its
optional C signedness convenience overload; ordinary ioctl ABI declarations,
nullability and availability remain. No headers are edited and no Clang identity
is invented.

The new positive fixture covers typedef returns, callbacks, nested pointers and
retained nullable runtime branches. Negative fixtures cover null calls,
conflicting qualifiers, newer calls/addresses, missing API and invalid fields.
They require exact-source execution. The initial local AArch64/API-24 repair
passed a real NDK-r29 header probe, but its unpublished build was lost when the
producer workspace changed. These reconstructed owned sources have not yet been
compiled: historical probe success is not acceptance of this revision.

ARM32/API-21 real-header, complete FastChat C compilation/linking, APK packaging
and physical MIRO A1 execution remain pending. Keep the original qualification
receipt as historical evidence; do not upgrade it merely because source exists.
