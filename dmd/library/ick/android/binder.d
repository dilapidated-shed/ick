module ick.android.binder;

public import ick.android.types;

alias AIBinder_DeathRecipient_onBinderDied =
    extern(C) void function(void* cookie) nothrow @nogc;

extern(C) nothrow @nogc:

binder_status_t AIBinder_ping(AIBinder* binder);
bool AIBinder_isAlive(const AIBinder* binder);

void AIBinder_incStrong(AIBinder* binder);
void AIBinder_decStrong(AIBinder* binder);

binder_status_t AIBinder_prepareTransaction(AIBinder* binder, AParcel** input);
binder_status_t AIBinder_transact(
    AIBinder* binder,
    transaction_code_t code,
    AParcel** input,
    AParcel** output,
    binder_flags_t flags
);

AIBinder_DeathRecipient* AIBinder_DeathRecipient_new(
    AIBinder_DeathRecipient_onBinderDied on_binder_died
);
void AIBinder_DeathRecipient_delete(AIBinder_DeathRecipient* recipient);
binder_status_t AIBinder_linkToDeath(
    AIBinder* binder,
    AIBinder_DeathRecipient* recipient,
    void* cookie
);
binder_status_t AIBinder_unlinkToDeath(
    AIBinder* binder,
    AIBinder_DeathRecipient* recipient,
    void* cookie
);

/* android/binder_ibinder_jni.h */
AIBinder* AIBinder_fromJavaBinder(JNIEnv* env, jobject binder);
jobject AIBinder_toJavaBinder(JNIEnv* env, AIBinder* binder);
