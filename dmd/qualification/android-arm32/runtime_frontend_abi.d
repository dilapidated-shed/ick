module runtime_frontend_abi;

version (Android) {} else static assert(0, "Android must be predefined");
version (ARM) {} else static assert(0, "ARM must be predefined");
version (ARM_SoftFP) {} else static assert(0, "AAPCS32 base PCS required");
version (CRuntime_Bionic) {} else static assert(0, "Bionic required");
import core.stdc.config : c_long_double;
import core.stdc.stdarg : va_list;
import core.stdc.stdio;
static assert(real.sizeof == 8 && c_long_double.sizeof == 8);
static assert(va_list.sizeof == (void*).sizeof);
static assert(is(typeof(va_list.init.__ap) == void*));
