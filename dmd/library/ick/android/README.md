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
- Parcel data-position/data-size inspection and repositioning;
- primitive, UTF-8 string and nullable UTF-8 string-array Parcel reads/writes plus Binder handles;
- ParcelFileDescriptor read/write;
- Java Binder conversion and Java-to-native Parcel conversion entry points;
- Android log write;
- the small Bionic process/PTY/pthread ABI surface required by Rish.

The string declarations follow the modern NDK C ABI: AParcel_stringAllocator
returns bool and receives an int32 length plus char** output buffer, while
AParcel_writeString takes int32 length. A null string is encoded by a null
pointer with length -1.

Public NDK Binder transactions and most primitive Parcel operations start at
Android API 29. AParcel_fromJavaParcel starts at API 30; AParcel_create and
AParcel_appendFrom start at API 31. Shizuku-API itself has a lower minimum
Android version, so this is not yet a complete compatibility replacement for
its Java Binder path.

For the Shizuku remote-transaction path specifically, public NDK exposes useful
pieces such as caller UID/PID, strong Binder reads, Parcel position/size,
`AParcel_appendFrom`, liveness, and death recipients. It is **not** by itself
an opaque Shizuku forwarding interface. `AIBinder_transact` requires its input
Parcel to come from `AIBinder_prepareTransaction`, and
`AIBinder_prepareTransaction` requires the target Binder to be associated with
an NDK Binder class. Shizuku instead accepts an arbitrary target Binder and
copies the caller's remaining opaque Parcel bytes.

The stable NDK also does **not** expose Java Binder's
`clearCallingIdentity()` / `restoreCallingIdentity()` pair. Exact Shizuku
forwarding therefore needs a narrow framework/JNI or platform-libbinder bridge
for the transparent transact/identity portion. These NDK declarations remain
useful around that bridge; they are not evidence that the bridge can be omitted.

The Bionic slice deliberately exposes only the process/PTY/pthread calls used by
Rish: fd I/O, fork/exec/wait, PTY setup, termios/window sizing, signals and
mutex/thread primitives. The ARM termios layout uses NCCS=19; pthread mutex
storage follows Bionic's LP32/LP64 ABI split.

JNI/Java framework bridges for Bundle, Intent,
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
