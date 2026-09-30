module ick.android.status;

public import ick.android.types;

extern(C) nothrow @nogc:

bool AStatus_isOk(const(AStatus)* status);
binder_exception_t AStatus_getExceptionCode(const(AStatus)* status);
binder_status_t AStatus_getStatus(const(AStatus)* status);
const(char)* AStatus_getMessage(const(AStatus)* status);
void AStatus_delete(AStatus* status);
