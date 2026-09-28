/** Exact finite geometry. Circle96 follows ick/include/ick/circle.h.
 * The same cyclic convention extends to the other explicitly named grids.
 * Storage is private; reconstruction of a raw code is checked, not wrapped.
 */
module icky.circle;

nothrow @nogc:

private template CodeStorage(uint positions)
{
    static if (positions <= 256) alias CodeStorage = ubyte;
    else alias CodeStorage = ushort;
}
private template TickStorage(uint positions)
{
    static if (positions <= 256) alias TickStorage = byte;
    else alias TickStorage = short;
}
private uint normalize(uint positions)(long ticks)
{
    long remainder = ticks % cast(long)positions;
    if (remainder < 0) remainder += positions;
    return cast(uint)remainder;
}

struct Circle(uint positions) if (positions >= 2 && positions <= 65536 && positions % 2 == 0)
{
    private CodeStorage!positions payload;
    private this(CodeStorage!positions raw) nothrow @nogc { payload = raw; }
    static Circle from_ticks(long ticks) nothrow @nogc
    {
        Circle result;
        result.payload = cast(CodeStorage!positions)normalize!positions(ticks);
        return result;
    }
    static bool try_from_code(uint code, ref Circle output) nothrow @nogc
    {
        if (code >= positions) return false;
        output.payload = cast(CodeStorage!positions)code;
        return true;
    }
    uint code() const nothrow @nogc { return payload; }
    static if (positions % 3 == 0)
    {
        uint third_sector() const nothrow @nogc { return payload / (positions / 3); }
        uint position_within_third() const nothrow @nogc { return payload % (positions / 3); }
    }
}

struct Rotation(uint positions) if (positions >= 2 && positions <= 65536 && positions % 2 == 0)
{
    private CodeStorage!positions payload;
    private this(CodeStorage!positions raw) nothrow @nogc { payload = raw; }
    static Rotation from_ticks(long ticks) nothrow @nogc
    {
        Rotation result;
        result.payload = cast(CodeStorage!positions)normalize!positions(ticks);
        return result;
    }
    static bool try_from_code(uint code, ref Rotation output) nothrow @nogc
    {
        if (code >= positions) return false;
        output.payload = cast(CodeStorage!positions)code;
        return true;
    }
    uint code() const nothrow @nogc { return payload; }
}

struct Reflection(uint positions) if (positions >= 2 && positions <= 65536 && positions % 2 == 0)
{
    private CodeStorage!positions payload;
    private this(CodeStorage!positions raw) nothrow @nogc { payload = raw; }
    static Reflection from_ticks(long ticks) nothrow @nogc
    {
        Reflection result;
        result.payload = cast(CodeStorage!positions)normalize!positions(ticks);
        return result;
    }
    static bool try_from_code(uint code, ref Reflection output) nothrow @nogc
    {
        if (code >= positions) return false;
        output.payload = cast(CodeStorage!positions)code;
        return true;
    }
    uint code() const nothrow @nogc { return payload; }
}

struct Tangent(uint positions) if (positions >= 2 && positions <= 65536 && positions % 2 == 0)
{
    private TickStorage!positions payload;
    private this(TickStorage!positions raw) nothrow @nogc { payload = raw; }
    static bool try_from_ticks(int ticks, ref Tangent output) nothrow @nogc
    {
        int half = cast(int)(positions / 2);
        if (ticks < -half || ticks >= half) return false;
        output.payload = cast(TickStorage!positions)ticks;
        return true;
    }
    int ticks() const nothrow @nogc { return payload; }
}

Circle!positions rotate(uint positions)(Rotation!positions amount, Circle!positions point)
{ return Circle!positions.from_ticks(cast(long)amount.code() + point.code()); }

Rotation!positions compose_rotations(uint positions)(Rotation!positions first, Rotation!positions second)
{ return Rotation!positions.from_ticks(cast(long)first.code() + second.code()); }

Rotation!positions inverse_rotation(uint positions)(Rotation!positions amount)
{ return Rotation!positions.from_ticks(-cast(long)amount.code()); }

Circle!positions reflect(uint positions)(Reflection!positions reflection, Circle!positions point)
{ return Circle!positions.from_ticks(cast(long)reflection.code() - point.code()); }

Tangent!positions local_displacement(uint positions)(Circle!positions to, Circle!positions from)
{
    int displacement = cast(int)to.code() - cast(int)from.code();
    int half = cast(int)(positions / 2);
    if (displacement >= half) displacement -= cast(int)positions;
    if (displacement < -half) displacement += cast(int)positions;
    Tangent!positions result;
    result.payload = cast(TickStorage!positions)displacement;
    return result;
}

Circle!positions displace(uint positions)(Circle!positions point, Tangent!positions tangent)
{ return Circle!positions.from_ticks(cast(long)point.code() + tangent.ticks()); }

alias Circle96 = Circle!96;
alias Rotation96 = Rotation!96;
alias Reflection96 = Reflection!96;
alias Tangent96 = Tangent!96;
alias Circle192 = Circle!192;
alias Rotation192 = Rotation!192;
alias Reflection192 = Reflection!192;
alias Tangent192 = Tangent!192;
alias Circle240 = Circle!240;
alias Rotation240 = Rotation!240;
alias Reflection240 = Reflection!240;
alias Tangent240 = Tangent!240;
alias Circle360 = Circle!360;
alias Rotation360 = Rotation!360;
alias Reflection360 = Reflection!360;
alias Tangent360 = Tangent!360;
alias Circle720 = Circle!720;
alias Rotation720 = Rotation!720;
alias Reflection720 = Reflection!720;
alias Tangent720 = Tangent!720;

Rotation96 one_third_turn96() { return Rotation96.from_ticks(32); }
Rotation96 two_thirds_turn96() { return Rotation96.from_ticks(64); }
Rotation96 one_flat96() { return Rotation96.from_ticks(16); }
Rotation96 half_flat96() { return Rotation96.from_ticks(8); }
Rotation96 quarter_flat96() { return Rotation96.from_ticks(4); }
Rotation96 eighth_flat96() { return Rotation96.from_ticks(2); }
Rotation96 sixteenth_flat96() { return Rotation96.from_ticks(1); }

static assert(Circle96.sizeof == 1 && Rotation96.sizeof == 1 && Reflection96.sizeof == 1 && Tangent96.sizeof == 1);
static assert(Circle192.sizeof == 1 && Circle240.sizeof == 1);
static assert(Circle360.sizeof == 2 && Circle720.sizeof == 2);
static assert(!is(Circle96 == Rotation96) && !is(Circle96 == Circle192));
