/**
 * ARMv7-A A32 instruction and ELF32 emission for Android armeabi-v7a.
 *
 * The public ABI is AAPCS32 base PCS (softfp): scalar floating-point
 * arguments/results travel in core registers even though VFPv3-D16
 * instructions are used for arithmetic.
 *
 * License: Boost License 1.0
 */
module dmd.backend.arm32;

import std.exception : enforce;

struct Arm32Code
{
    ubyte[] bytes;

    void instruction(uint value)
    {
        foreach (i; 0 .. 4)
            bytes ~= cast(ubyte)(value >> (i * 8));
    }

    private uint readInstruction(size_t at) const
    {
        enforce(at + 4 <= bytes.length, "A32 read outside instruction stream");
        return cast(uint)bytes[at] |
               cast(uint)bytes[at + 1] << 8 |
               cast(uint)bytes[at + 2] << 16 |
               cast(uint)bytes[at + 3] << 24;
    }

    void patchInstruction(size_t at, uint value)
    {
        enforce(at + 4 <= bytes.length && !(at & 3), "A32 patch outside instruction stream");
        foreach (i; 0 .. 4)
            bytes[at + i] = cast(ubyte)(value >> (i * 8));
    }

    void constant(uint value, uint reg = 0)
    {
        enforce(reg < 4, "A32 constant register outside r0-r3");
        const lo = value & 0xFFFF;
        const hi = value >> 16;
        instruction(0xE3000000 | ((lo & 0xF000) << 4) | (reg << 12) | (lo & 0x0FFF)); // MOVW
        instruction(0xE3400000 | ((hi & 0xF000) << 4) | (reg << 12) | (hi & 0x0FFF)); // MOVT
    }

    size_t loadStackOffset(uint offset, uint reg = 0)
    {
        enforce(offset <= 4095 && reg < 4, "A32 stack load out of range");
        const at = bytes.length;
        instruction(0xE59D0000 | reg << 12 | offset); // LDR Rd,[sp,#offset]
        return at;
    }

    void patchLoadStackOffset(size_t at, uint offset, uint reg = 0)
    {
        enforce(offset <= 4095 && reg < 4, "A32 patched stack load out of range");
        patchInstruction(at, 0xE59D0000 | reg << 12 | offset);
    }

    void storeStackOffset(uint offset, uint reg = 0)
    {
        enforce(offset <= 4095 && reg < 4, "A32 stack store out of range");
        instruction(0xE58D0000 | reg << 12 | offset); // STR Rd,[sp,#offset]
    }

    void load(uint slot, uint reg = 0)
    {
        enforce(slot < 126, "A32 stack slot out of range");
        loadStackOffset(slot * 4, reg);
    }

    void store(uint slot, uint reg = 0)
    {
        enforce(slot < 126, "A32 stack slot out of range");
        storeStackOffset(slot * 4, reg);
    }

    void adjustStack(uint amount, bool subtract)
    {
        enforce(!(amount & 7) && amount <= 504,
                "A32 dynamic stack adjustment must be 8-byte aligned and <= 504 bytes");
        uint first = amount > 252 ? 252 : amount;
        uint second = amount - first;
        const base = subtract ? 0xE24DD000 : 0xE28DD000; // SUB/ADD sp,sp,#imm8
        if (first)
            instruction(base | first);
        if (second)
            instruction(base | second);
    }

    size_t call()
    {
        const at = bytes.length;
        // This is the canonical zero-addend R_ARM_CALL placeholder emitted by
        // the GNU/LLVM ARM assemblers: BL with imm24=-2 (PC bias -8).
        instruction(0xEBFFFFFE);
        return at;
    }

    size_t branch(uint condition = 14)
    {
        enforce(condition < 15, "invalid A32 branch condition");
        const at = bytes.length;
        instruction(condition << 28 | 0x0A000000);
        return at;
    }

    void resolve(size_t at, size_t destination)
    {
        enforce(!(at & 3) && !(destination & 3), "unaligned A32 branch");
        const delta = cast(long)destination - cast(long)at - 8;
        enforce(!(delta & 3) && delta >= -33_554_432 && delta <= 33_554_428,
                "A32 branch displacement out of range");
        const current = readInstruction(at);
        patchInstruction(at, (current & 0xFF000000) |
                             (cast(uint)(delta >> 2) & 0x00FF_FFFF));
    }

    size_t conditional(uint condition)
    {
        return branch(condition);
    }

    void booleanResult(uint condition)
    {
        enforce(condition < 14, "invalid A32 boolean condition");
        instruction(0xE3A00000);                         // MOV r0,#0
        instruction(condition << 28 | 0x03A00001);       // MOV<cond> r0,#1
    }

    void patchFrame(size_t at, uint frame, bool subtract)
    {
        enforce(!(frame & 7) && frame <= 504, "A32 frame must be 8-byte aligned and <= 504 bytes");
        uint first = frame > 252 ? 252 : frame;
        uint second = frame - first;
        const base = subtract ? 0xE24DD000 : 0xE28DD000; // SUB/ADD sp,sp,#imm8
        patchInstruction(at, first ? base | first : 0xE1A00000);
        patchInstruction(at + 4, second ? base | second : 0xE1A00000);
    }
}

struct Arm32Relocation
{
    uint offset;
    string symbol;
}

struct Arm32Function
{
    string name;
    ubyte[] code;
    Arm32Relocation[] relocations;
}

private void word(ref ubyte[] bytes, uint value)
{
    foreach (i; 0 .. 4)
        bytes ~= cast(ubyte)(value >> (i * 8));
}

private void half(ref ubyte[] bytes, uint value)
{
    bytes ~= cast(ubyte)value;
    bytes ~= cast(ubyte)(value >> 8);
}

/**
 * ELF32 ARM object containing A32 functions and R_ARM_CALL relocations.
 *
 * The ELF flags and .ARM.attributes describe EABI5 + base PCS/softfp.
 * There is intentionally no EF_ARM_ABI_FLOAT_HARD flag.
 */
ubyte[] arm32Object(Arm32Function[] functions)
{
    enum R_ARM_CALL = 28;

    ubyte[] text;
    Arm32Relocation[] relocations;
    uint[string] functionOffsets;

    foreach (function_; functions)
    {
        while (text.length & 3)
            text ~= 0;
        const base = cast(uint)text.length;
        functionOffsets[function_.name] = base;
        foreach (relocation; function_.relocations)
            relocations ~= Arm32Relocation(base + relocation.offset, relocation.symbol);
        text ~= function_.code;
    }

    ubyte[] strings = [0];
    ubyte[] symbols;
    symbols.length = 16; // mandatory undefined symbol
    uint[string] symbolIndex;

    uint name(string value)
    {
        const start = cast(uint)strings.length;
        strings ~= cast(const(ubyte)[])value;
        strings ~= 0;
        return start;
    }

    uint symbol(uint nameOffset, uint value, uint size, ubyte info, ushort section)
    {
        const index = cast(uint)(symbols.length / 16);
        word(symbols, nameOffset);
        word(symbols, value);
        word(symbols, size);
        symbols ~= info;
        symbols ~= 0;
        half(symbols, section);
        return index;
    }

    symbol(name("$a"), 0, 0, 0, 1); // local A32 mapping symbol

    foreach (function_; functions)
    {
        const index = symbol(name(function_.name), functionOffsets[function_.name],
                             cast(uint)function_.code.length, 0x12, 1); // GLOBAL FUNC
        symbolIndex[function_.name] = index;
    }

    bool[string] undefinedSeen;
    foreach (relocation; relocations)
    {
        if (relocation.symbol in symbolIndex || relocation.symbol in undefinedSeen)
            continue;
        undefinedSeen[relocation.symbol] = true;
        const index = symbol(name(relocation.symbol), 0, 0, 0x12, 0); // undefined GLOBAL FUNC
        symbolIndex[relocation.symbol] = index;
    }

    ubyte[] relText;
    foreach (relocation; relocations)
    {
        auto index = relocation.symbol in symbolIndex;
        enforce(index !is null, "A32 relocation references missing symbol");
        word(relText, relocation.offset);
        word(relText, (*index << 8) | R_ARM_CALL);
    }

    // aeabi: v7-A, ARM ISA, no Thumb requirement, VFPv3-D16,
    // 8-byte public stack alignment, base PCS (softfp arguments).
    ubyte[] tags = [6, 10, 7, 65, 8, 1, 9, 0, 10, 4, 24, 1, 25, 1, 28, 0];
    ubyte[] attributes = [cast(ubyte)'A'];
    word(attributes, cast(uint)(4 + 6 + 5 + tags.length));
    attributes ~= cast(const(ubyte)[])"aeabi\0";
    attributes ~= 1;
    word(attributes, cast(uint)(5 + tags.length));
    attributes ~= tags;

    ubyte[] sectionNames = [0];
    uint[8] sectionNameOffsets;
    immutable string[8] sectionNameValues =
        ["", ".text", ".rel.text", ".symtab", ".strtab", ".shstrtab", ".ARM.attributes", ".note.GNU-stack"];
    foreach (i; 1 .. sectionNameValues.length)
    {
        sectionNameOffsets[i] = cast(uint)sectionNames.length;
        sectionNames ~= cast(const(ubyte)[])sectionNameValues[i];
        sectionNames ~= 0;
    }

    ubyte[][] contents = [null, text, relText, symbols, strings, sectionNames, attributes, null];
    uint[8] offsets;
    ubyte[] result;
    result.length = 52;

    foreach (i; 1 .. contents.length)
    {
        while (result.length & 3)
            result ~= 0;
        offsets[i] = cast(uint)result.length;
        result ~= contents[i];
    }

    while (result.length & 3)
        result ~= 0;
    const sectionOffset = cast(uint)result.length;

    immutable uint[8] types = [0, 1, 9, 2, 3, 3, 0x70000003, 1];
    foreach (i; 0 .. 8)
    {
        word(result, sectionNameOffsets[i]);
        word(result, types[i]);
        word(result, i == 1 ? 6 : 0);               // .text: ALLOC | EXECINSTR
        word(result, 0);
        word(result, offsets[i]);
        word(result, cast(uint)contents[i].length);
        word(result, i == 2 ? 3 : i == 3 ? 4 : 0); // rel->symtab; symtab->strtab
        word(result, i == 2 ? 1 : i == 3 ? 2 : 0); // rel applies to .text; first global symbol
        word(result, i == 0 ? 0 : (i == 1 || i == 2 || i == 3 ? 4 : 1));
        word(result, i == 2 ? 8 : i == 3 ? 16 : 0);
    }

    ubyte[] header = [0x7F, 'E', 'L', 'F', 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    half(header, 1);                    // ET_REL
    half(header, 40);                   // EM_ARM
    word(header, 1);                    // EV_CURRENT
    word(header, 0);                    // e_entry
    word(header, 0);                    // e_phoff
    word(header, sectionOffset);
    word(header, 0x05000000);           // EABI5, no hard-float ABI flag
    half(header, 52);
    half(header, 0);
    half(header, 0);
    half(header, 40);
    half(header, 8);
    half(header, 5);
    result[0 .. 52] = header;
    return result;
}
