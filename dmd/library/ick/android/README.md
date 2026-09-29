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
- primitive Parcel reads/writes and Binder handles;
- Java Binder/Parcel conversion entry points;
- Android log write.

The NDK Binder surface used here starts at Android API 29. Shizuku-API itself
currently has a lower minimum Android version, so this is not yet a complete
compatibility replacement for its Java Binder path. JNI/Java framework bridges
for Bundle, Intent, ComponentName, ContentProvider, Looper/Handler and older
Android releases remain explicit missing touch points.

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
