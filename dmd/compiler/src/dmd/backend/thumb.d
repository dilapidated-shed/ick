/**
 * ARMv7-A Thumb-2 leaf instruction and ELF32 emission.
 *
 * The softfp boundary and stack-home strategy follow the native-arm line of
 * fuego-ironworks/idric-arm-thumb. This emitter produces bytes itself; it does
 * not translate D through C or invoke another compiler.
 *
 * License: Boost License 1.0
 */
module dmd.backend.thumb;

import std.exception : enforce;

struct ThumbCode
{
    ubyte[] bytes;

    void half(uint value)
    {
        bytes ~= cast(ubyte)value;
        bytes ~= cast(ubyte)(value >> 8);
    }

    void wide(uint first, uint second) { half(first); half(second); }

    void patch_half(size_t at, uint value)
    {
        enforce(at + 2 <= bytes.length, "Thumb patch outside instruction stream");
        bytes[at] = cast(ubyte)value;
        bytes[at + 1] = cast(ubyte)(value >> 8);
    }

    // All public operations use caller-saved low registers only.
    void constant(uint value, uint reg = 0)
    {
        enforce(reg < 4, "Thumb constant register outside r0-r3");
        void piece(uint opcode, uint word)
        {
            wide(opcode | ((word >> 11) & 1) << 10 | ((word >> 12) & 15),
                 ((word >> 8) & 7) << 12 | reg << 8 | (word & 255));
        }
        piece(0xF240, value & 65535);  // MOVW
        piece(0xF2C0, value >> 16);    // MOVT
    }

    void load(uint slot, uint reg = 0)
    {
        enforce(slot < 126 && reg < 4, "Thumb stack load out of range");
        half(0x9800 | reg << 8 | slot);
    }

    void store(uint slot, uint reg = 0)
    {
        enforce(slot < 126 && reg < 4, "Thumb stack store out of range");
        half(0x9000 | reg << 8 | slot);
    }

    // Canonical unresolved Thumb-2 BL. ARM ELF uses REL rather than RELA;
    // the encoded -4 addend accounts for Thumb PC+4 semantics.
    size_t call()
    {
        auto at = bytes.length;
        wide(0xF7FF, 0xFFFE);
        return at;
    }

    // A wide branch has a signed 25-bit byte displacement from PC+4.
    // Use it for every long edge so source size cannot silently wrap a branch.
    size_t branch()
    {
        auto at = bytes.length;
        wide(0xF000, 0xB800);
        return at;
    }

    void resolve(size_t at, size_t destination)
    {
        const delta = cast(long)destination - cast(long)at - 4;
        enforce(!(delta & 1) && delta >= -16_777_216 && delta <= 16_777_214,
                "Thumb branch displacement out of range");
        const bits = cast(uint)delta;
        const s = (bits >> 24) & 1;
        const j1 = (~((bits >> 23) ^ s)) & 1;
        const j2 = (~((bits >> 22) ^ s)) & 1;
        patch_half(at, 0xF000 | s << 10 | ((bits >> 12) & 1023));
        patch_half(at + 2, 0x9000 | j1 << 13 | j2 << 11 | ((bits >> 1) & 2047));
    }

    size_t conditional(uint condition)
    {
        enforce(condition < 14, "Invalid Thumb condition");
        // The inverse short branch skips precisely the following B.W.
        half(0xD000 | (condition ^ 1) << 8 | 1);
        return branch();
    }

    void boolean_result(uint condition)
    {
        auto yes = conditional(condition);
        half(0x2000); // MOVS r0, #0
        auto done = branch();
        resolve(yes, bytes.length);
        half(0x2001); // MOVS r0, #1
        resolve(done, bytes.length);
    }
}

struct ThumbCall
{
    size_t offset;
    string symbol;
}

struct ThumbFunction
{
    string name;
    ubyte[] code;
    ThumbCall[] calls;
}

private void word(ref ubyte[] bytes, uint value)
{
    foreach (i; 0 .. 4) bytes ~= cast(ubyte)(value >> (i * 8));
}

private void half(ref ubyte[] bytes, uint value)
{
    bytes ~= cast(ubyte)value;
    bytes ~= cast(ubyte)(value >> 8);
}

/**
 * ELF32 ARM object for independent Thumb-2 functions.
 *
 * Direct calls use the ordinary ARM ELF `.rel.text` / `R_ARM_THM_CALL`
 * contract. The BL instruction stores its implicit REL addend; the relocation
 * points at either another function in this object or an undefined external
 * symbol for the final linker.
 */
ubyte[] thumb_object(ThumbFunction[] functions)
{
    ubyte[] text, relocations, strings = [0], symbols;
    symbols.length = 16; // mandatory undefined symbol

    uint name(string value)
    {
        auto start = cast(uint)strings.length;
        strings ~= cast(const(ubyte)[])value;
        strings ~= 0;
        return start;
    }

    uint symbol(uint name_offset, uint value, uint size, ubyte info, uint section)
    {
        const index = cast(uint)(symbols.length / 16);
        word(symbols, name_offset);
        word(symbols, value);
        word(symbols, size);
        symbols ~= info;
        symbols ~= 0;
        half(symbols, section);
        return index;
    }

    uint[string] symbol_indices;
    symbol(name("$t"), 0, 0, 0, 1); // local Thumb mapping symbol

    struct PendingRelocation
    {
        uint offset;
        string symbol;
    }
    PendingRelocation[] pending;

    foreach (function_; functions)
    {
        while (text.length % 4)
        {
            text ~= 0;
            text ~= 0xBF; // Thumb NOP
        }

        const start = cast(uint)text.length;
        const index = symbol(
            name(function_.name),
            start | 1,
            cast(uint)function_.code.length,
            0x12, // GLOBAL FUNC
            1
        );
        symbol_indices[function_.name] = index;

        foreach (call; function_.calls)
            pending ~= PendingRelocation(
                start + cast(uint)call.offset,
                call.symbol
            );

        text ~= function_.code;
    }

    foreach (relocation; pending)
    {
        uint target;
        if (auto found = relocation.symbol in symbol_indices)
            target = *found;
        else
        {
            target = symbol(
                name(relocation.symbol),
                0,
                0,
                0x10, // GLOBAL NOTYPE, matching ordinary assemblers
                0
            );
            symbol_indices[relocation.symbol] = target;
        }

        word(relocations, relocation.offset);
        word(relocations, (target << 8) | 10); // R_ARM_THM_CALL
    }

    // aeabi Tag_File: v7-A, Thumb-2, VFPv3-D16, 8-byte stack, base PCS.
    ubyte[] tags = [6, 10, 7, 65, 8, 0, 9, 2, 10, 4, 24, 1, 25, 1, 28, 0];
    ubyte[] attributes = [cast(ubyte)'A'];
    word(attributes, cast(uint)(4 + 6 + 5 + tags.length));
    attributes ~= cast(const(ubyte)[])"aeabi\0";
    attributes ~= 1;
    word(attributes, cast(uint)(5 + tags.length));
    attributes ~= tags;

    ubyte[] section_names = [0];
    uint section_name(string value)
    {
        const offset = cast(uint)section_names.length;
        section_names ~= cast(const(ubyte)[])value;
        section_names ~= 0;
        return offset;
    }

    uint[8] names = [
        0,
        section_name(".text"),
        section_name(".rel.text"),
        section_name(".symtab"),
        section_name(".strtab"),
        section_name(".shstrtab"),
        section_name(".ARM.attributes"),
        section_name(".note.GNU-stack")
    ];

    ubyte[][] contents = [
        null,
        text,
        relocations,
        symbols,
        strings,
        section_names,
        attributes,
        null
    ];

    uint[8] offsets;
    ubyte[] result;
    result.length = 52; // ELF header, filled below
    foreach (i; 1 .. 8)
    {
        while (result.length % 4) result ~= 0;
        offsets[i] = cast(uint)result.length;
        result ~= contents[i];
    }

    while (result.length % 4) result ~= 0;
    const section_offset = cast(uint)result.length;

    uint[8] types = [
        0,
        1,          // SHT_PROGBITS .text
        9,          // SHT_REL .rel.text
        2,          // SHT_SYMTAB
        3,          // SHT_STRTAB
        3,          // SHT_STRTAB
        0x70000003, // SHT_ARM_ATTRIBUTES
        1
    ];

    foreach (i; 0 .. 8)
    {
        word(result, names[i]);
        word(result, types[i]);
        word(result, i == 1 ? 6 : 0); // .text: ALLOC | EXECINSTR
        word(result, 0);
        word(result, offsets[i]);
        word(result, cast(uint)contents[i].length);

        uint link = 0;
        uint info = 0;
        uint alignment = i == 0 ? 0 : 1;
        uint entry_size = 0;

        if (i == 2)
        {
            link = 3;      // .rel.text -> .symtab
            info = 1;      // relocation applies to .text
            alignment = 4;
            entry_size = 8;
        }
        else if (i == 3)
        {
            link = 4;      // .symtab -> .strtab
            info = 2;      // first global symbol
            alignment = 4;
            entry_size = 16;
        }
        else if (i == 1)
            alignment = 4;

        word(result, link);
        word(result, info);
        word(result, alignment);
        word(result, entry_size);
    }

    ubyte[] header = [0x7F, 'E', 'L', 'F', 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    half(header, 1);
    half(header, 40); // ET_REL, EM_ARM
    word(header, 1);
    word(header, 0);
    word(header, 0);
    word(header, section_offset);
    word(header, 0x05000000); // EABI version 5
    half(header, 52);
    half(header, 0);
    half(header, 0);
    half(header, 40);
    half(header, 8);
    half(header, 5); // .shstrtab
    result[0 .. 52] = header;
    return result;
}
