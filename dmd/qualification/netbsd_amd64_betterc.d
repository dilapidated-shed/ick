module netbsd_amd64_betterc;

version (NetBSD) {}
else static assert(0, "NetBSD target version was not defined");

version (Posix) {}
else static assert(0, "Posix target version was not defined");

version (X86_64) {}
else static assert(0, "X86_64 target version was not defined");

extern(C) int netbsd_add(int a, int b)
{
    return a + b;
}
