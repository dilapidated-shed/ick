module android_interfaces_compile;

import ick.android;

static assert(binder_status_t.sizeof == 4);
static assert(transaction_code_t.sizeof == 4);
static assert(binder_flags_t.sizeof == 4);
static assert(AIBinder*.sizeof == void*.sizeof);
static assert(AParcel*.sizeof == void*.sizeof);

extern(C) int android_interfaces_compile_probe(AIBinder* binder, AParcel* parcel)
{
    return binder is null || parcel is null ? -1 : 0;
}
