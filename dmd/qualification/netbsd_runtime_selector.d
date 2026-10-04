module netbsd_runtime_selector;

version (NetBSD) {}
else static assert(0, "selector fixture requires the NetBSD target");
version (X86_64) {}
else static assert(0, "selector fixture requires amd64");

// Compile the real pinned druntime backtrace consumer, including the
// Image.openSelf() expression that fails at dwarf.d:166 without the selector.
import core.internal.backtrace.dwarf : traceHandlerOpApplyImpl;

int exerciseBacktraceSelector()
{
    return traceHandlerOpApplyImpl(0, null, null, null);
}
