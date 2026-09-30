module ick.android.binder;

public import ick.android.types;

alias AIBinder_Class_onCreate =
    extern(C) void* function(void* args) nothrow @nogc;
alias AIBinder_Class_onDestroy =
    extern(C) void function(void* user_data) nothrow @nogc;
alias AIBinder_Class_onTransact =
    extern(C) binder_status_t function(
        AIBinder* binder,
        transaction_code_t code,
        const AParcel* input,
        AParcel* output
    ) nothrow @nogc;

alias AIBinder_DeathRecipient_onBinderDied =
    extern(C) void function(void* cookie) nothrow @nogc;

extern(C) nothrow @nogc:

AIBinder_Class* AIBinder_Class_define(
    const char* interface_descriptor,
    AIBinder_Class_onCreate on_create,
    AIBinder_Class_onDestroy on_destroy,
    AIBinder_Class_onTransact on_transact
);
AIBinder* AIBinder_new(const AIBinder_Class* clazz, void* args);
bool AIBinder_associateClass(AIBinder* binder, const AIBinder_Class* clazz);
const AIBinder_Class* AIBinder_getClass(AIBinder* binder);
void* AIBinder_getUserData(AIBinder* binder);

bool AIBinder_isRemote(const AIBinder* binder);
binder_status_t AIBinder_ping(AIBinder* binder);
bool AIBinder_isAlive(const AIBinder* binder);

void AIBinder_incStrong(AIBinder* binder);
void AIBinder_decStrong(AIBinder* binder);

uint AIBinder_getCallingUid();
int AIBinder_getCallingPid();

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
