# Android touch points for Icky DMD

This directory owns the D declarations for the Android C ABI that translated
programs may touch. Application repositories should import these modules
instead of redeclaring Android ABI details locally.

The first consumer is the D translation of Shizuku-API.

## Boundary in this first slice

Defined now:

- opaque Binder and Parcel handle types;
- Binder status, transaction-code and flag types;
- binder liveness and strong-reference operations;
- transaction preparation and dispatch;
- death-recipient creation/link/unlink;
- primitive and UTF-8 string Parcel reads/writes plus Binder handles;
- Java Binder conversion and Java-to-native Parcel conversion entry points;
- Android log write.

Public NDK Binder transactions and most primitive Parcel operations start at
Android API 29. AParcel_fromJavaParcel starts at API 30; AParcel_create and
AParcel_appendFrom start at API 31. Shizuku-API itself has a lower minimum
Android version, so this is not yet a complete compatibility replacement for
its Java Binder path. JNI/Java framework bridges for Bundle, Intent,
ComponentName, ContentProvider, Looper/Handler and older Android releases remain
explicit missing touch points.

## Compiler qualification status

The dmd-android-arm-backends branch currently qualifies freestanding scalar
leaves. Its admission gate still rejects general calls/relocations and it does
not qualify Bionic, libbinder_ndk, JNI, druntime or Phobos on Android.

Accordingly, these declarations define the ABI seam but do not claim that
Icky DMD can yet build or run the Shizuku Binder client. The next compiler gate
is external-call lowering/relocations followed by device tests linked against
the relevant Android libraries.

Declarations mirror the Android NDK C API rather than wrapping it in a second
object model. Higher-level ownership and protocol logic belongs in consumers.
