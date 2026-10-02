module ick.android.types;

/**
 * C ABI names used by Android NDK Binder and Binder/JNI bridge headers.
 *
 * These types are intentionally only used behind pointers. The Android headers
 * keep the corresponding structs opaque as well.
 */

extern(C) struct AIBinder {}
extern(C) struct AIBinder_Class {}
extern(C) struct AIBinder_DeathRecipient {}
extern(C) struct AParcel {}
extern(C) struct AStatus {}

extern(C) struct JNIEnv {}
extern(C) struct JavaVM {}

alias jobject = void*;
alias jclass = jobject;
alias jstring = jobject;
alias jthrowable = jobject;

alias jint = int;
alias jlong = long;
alias jboolean = ubyte;

alias binder_status_t = int;
alias binder_exception_t = int;
alias transaction_code_t = uint;
alias binder_flags_t = uint;

enum binder_status_t STATUS_OK = 0;
enum binder_status_t STATUS_PERMISSION_DENIED = -1; // -EPERM
enum binder_status_t STATUS_NO_MEMORY = -12; // -ENOMEM
enum binder_status_t STATUS_BAD_VALUE = -22; // -EINVAL
enum binder_status_t STATUS_UNKNOWN_TRANSACTION = -74; // -EBADMSG on Linux/Android
enum binder_flags_t FLAG_ONEWAY = 0x01;
