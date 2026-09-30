module ick.android.parcel;

public import ick.android.types;

/*
 * android/binder_parcel.h:
 *   typedef char* (*AParcel_stringAllocator)(void* stringData, size_t length);
 */
alias AParcel_stringAllocator =
    extern(C) char* function(void* string_data, size_t length) nothrow @nogc;

extern(C) nothrow @nogc:

/* AParcel_create is API 31; transaction parcels come from AIBinder_prepareTransaction on API 29+. */
AParcel* AParcel_create();
void AParcel_delete(AParcel* parcel);

binder_status_t AParcel_writeStatusHeader(AParcel* parcel, const AStatus* status);
binder_status_t AParcel_readStatusHeader(const AParcel* parcel, AStatus** status);

binder_status_t AParcel_writeInt32(AParcel* parcel, int value);
binder_status_t AParcel_readInt32(const AParcel* parcel, int* value);

binder_status_t AParcel_writeUint32(AParcel* parcel, uint value);
binder_status_t AParcel_readUint32(const AParcel* parcel, uint* value);

binder_status_t AParcel_writeBool(AParcel* parcel, bool value);
binder_status_t AParcel_readBool(const AParcel* parcel, bool* value);

binder_status_t AParcel_writeString(AParcel* parcel, const char* value, size_t length);
binder_status_t AParcel_readString(
    const AParcel* parcel,
    void* string_data,
    AParcel_stringAllocator allocator
);

binder_status_t AParcel_writeStrongBinder(AParcel* parcel, AIBinder* binder);
binder_status_t AParcel_readStrongBinder(const AParcel* parcel, AIBinder** binder);
binder_status_t AParcel_readNullableStrongBinder(const AParcel* parcel, AIBinder** binder);

binder_status_t AParcel_writeParcelFileDescriptor(AParcel* parcel, int fd);
binder_status_t AParcel_readParcelFileDescriptor(const AParcel* parcel, int* fd);

/* API 31 */
binder_status_t AParcel_appendFrom(
    const AParcel* from,
    AParcel* to,
    int start,
    int size
);

/* android/binder_parcel_jni.h, API 30 */
AParcel* AParcel_fromJavaParcel(JNIEnv* env, jobject parcel);
