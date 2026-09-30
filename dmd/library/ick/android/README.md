# Android touch points for Icky DMD

This directory owns the D declarations for the Android C ABI that translated
programs may touch. Application repositories should import these modules
instead of redeclaring Android ABI details locally.

The first consumer is the D translation of Shizuku-API.

## Boundary in this slice

Defined now:

- opaque Binder, Parcel and Status handle types;
- Binder status, exception, transaction-code and flag types;
- binder liveness and strong-reference operations;
- transaction preparation and dispatch;
- death-recipient creation/link/unlink;
- Binder transaction status-header read/write and status inspection/deletion;
- primitive and UTF-8 string Parcel reads/writes plus Binder handles;
- ParcelFileDescriptor read/write;
- Java Binder conversion and Java-to-native Parcel conversion entry points;
- Android log write.

The string allocator and string-length declarations intentionally follow the
NDK C header exactly: AParcel_stringAllocator returns a char pointer and takes
size_t, and AParcel_writeString takes size_t. Earlier declarations on this
branch used a bool/out-pointer allocator shape and int length; those were ABI
mismatches found while translating Shizuku-API.

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
