module ick.android.log;

enum AndroidLogPriority : int {
    unknown = 0,
    default_ = 1,
    verbose = 2,
    debug_ = 3,
    info = 4,
    warn = 5,
    error = 6,
    fatal = 7,
    silent = 8
}

extern(C) nothrow @nogc int __android_log_write(
    int priority,
    const(char)* tag,
    const(char)* text
);
