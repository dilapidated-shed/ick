module ick.android.parcel;

public import ick.android.types;

extern(C) nothrow @nogc:

AParcel* AParcel_create();
void AParcel_delete(AParcel* parcel);

binder_status_t AParcel_writeInt32(AParcel* parcel, int value);
binder_status_t AParcel_readInt32(const AParcel* parcel, int* value);

binder_status_t AParcel_writeUint32(AParcel* parcel, uint value);
binder_status_t AParcel_readUint32(const AParcel* parcel, uint* value);

binder_status_t AParcel_writeBool(AParcel* parcel, bool value);
binder_status_t AParcel_readBool(const AParcel* parcel, bool* value);

binder_status_t AParcel_writeStrongBinder(AParcel* parcel, AIBinder* binder);
binder_status_t AParcel_readStrongBinder(const AParcel* parcel, AIBinder** binder);

binder_status_t AParcel_appendFrom(
    const AParcel* from,
    AParcel* to,
    int start,
    int size
);

/* android/binder_parcel_jni.h */
AParcel* AParcel_fromJavaParcel(JNIEnv* env, jobject parcel);
jobject AParcel_toJavaParcel(JNIEnv* env, AParcel* parcel);
