module ordinary_d;

version (Android) {} else static assert(0, "Android version must be predefined");
version (ARM) {} else static assert(0, "ARM version must be predefined");
version (ARM_SoftFP) {} else static assert(0, "base PCS must be selected");
version (CRuntime_Bionic) {} else static assert(0, "Bionic must be selected");
version (D_ModuleInfo) {} else static assert(0, "ordinary D must retain ModuleInfo");
static assert(void*.sizeof == 4);
static assert(size_t.sizeof == 4);

// This deliberately omits -betterC.  It uses no allocation, exceptions, or
// constructors, so the first normal-D object should carry only standalone
// ModuleInfo through the druntime minfo contract.
extern(C) export int ordinary_d_add(int left, int right)
{
    return left + right;
}
