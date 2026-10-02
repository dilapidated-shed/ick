module netbsd_amd64_normal_d;

import std.file : exists;
import std.regex : matchFirst, regex;
import std.stdio : File;

version (NetBSD) {}
else static assert(0, "NetBSD target version was not defined");

version (Posix) {}
else static assert(0, "Posix target version was not defined");

version (X86_64) {}
else static assert(0, "X86_64 target version was not defined");

static assert(size_t.sizeof == 8);
static assert(void*.sizeof == 8);

int matchSpecList(string text)
{
    auto matcher = regex("SPEC-LIST", "i");
    return matchFirst(text, matcher) ? 1 : 0;
}

size_t allocateAndTouch(size_t bytes)
{
    auto buffer = new ubyte[](bytes);
    if (buffer.length != 0)
    {
        buffer[0] = 0x2a;
        buffer[$ - 1] = 0x17;
    }
    return buffer.length;
}

int throwAndCatch()
{
    try
    {
        throw new Exception("netbsd-normal-d");
    }
    catch (Exception error)
    {
        return error.msg == "netbsd-normal-d" ? 1 : 0;
    }
}

bool fileExists(string path)
{
    return exists(path);
}

size_t openAndMeasure(string path)
{
    auto file = File(path, "rb");
    return cast(size_t) file.size;
}
