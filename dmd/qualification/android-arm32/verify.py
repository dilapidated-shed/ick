#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
import subprocess
from collections import Counter
from pathlib import Path


def run(command: list[str]) -> None:
    print("+", " ".join(command))
    subprocess.run(command, check=True, timeout=60)


def check_elf(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise RuntimeError("not an ELF object")
    if data[4:9] != bytes([1, 1, 1, 0, 0]):
        raise RuntimeError("expected ELF32 little-endian System-V object")
    e_type, e_machine = struct.unpack_from("<HH", data, 16)
    if (e_type, e_machine) != (1, 40):
        raise RuntimeError(f"expected ET_REL/EM_ARM, got {e_type}/{e_machine}")
    flags = struct.unpack_from("<I", data, 36)[0]
    if flags != 0x05000000:
        raise RuntimeError(f"expected EABI5 without hard-float flag, got {flags:#x}")

    shoff = struct.unpack_from("<I", data, 32)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 46)
    if shentsize != 40 or shnum < 8 or shstrndx >= shnum:
        raise RuntimeError("unexpected ELF32 section table")

    sections = []
    for i in range(shnum):
        at = shoff + i * shentsize
        sections.append(struct.unpack_from("<IIIIIIIIII", data, at))

    shstr = sections[shstrndx]
    shstr_data = data[shstr[4]:shstr[4] + shstr[5]]

    def cstring(blob: bytes, offset: int) -> str:
        end = blob.find(b"\0", offset)
        if end < 0:
            raise RuntimeError("unterminated ELF string")
        return blob[offset:end].decode("ascii")

    section_by_name = {}
    for i, section in enumerate(sections):
        section_by_name[cstring(shstr_data, section[0]) if section[0] else ""] = (i, section)

    for required in [".text", ".rel.text", ".data", ".symtab", ".strtab", ".ARM.attributes"]:
        if required not in section_by_name:
            raise RuntimeError(f"missing ELF section {required}")

    text_index, _ = section_by_name[".text"]
    rel_index, rel = section_by_name[".rel.text"]
    data_index, data_section = section_by_name[".data"]
    sym_index, sym = section_by_name[".symtab"]
    str_index, strings = section_by_name[".strtab"]

    if rel[1] != 9 or rel[6] != sym_index or rel[7] != text_index or rel[9] != 8:
        raise RuntimeError("malformed .rel.text section linkage")
    if sym[1] != 2 or sym[6] != str_index or sym[9] != 16:
        raise RuntimeError("malformed .symtab section linkage")

    str_data = data[strings[4]:strings[4] + strings[5]]
    symbols = []
    for at in range(sym[4], sym[4] + sym[5], 16):
        name_off, value, size = struct.unpack_from("<III", data, at)
        info, other, shndx = struct.unpack_from("<BBH", data, at + 12)
        symbols.append((cstring(str_data, name_off) if name_off else "", value, size, info, other, shndx))

    for name, value, _, info, _, shndx in symbols:
        if shndx == text_index and (info & 0xF) == 2 and value & 3:
            raise RuntimeError(f"A32 function symbol {name} is not word aligned: {value:#x}")

    external = [s for s in symbols if s[0] == "external_twice"]
    if len(external) != 1 or external[0][5] != 0:
        raise RuntimeError("external_twice must be one undefined ELF function symbol")

    external_data = [s for s in symbols if s[0] == "external_global"]
    if len(external_data) != 1 or external_data[0][5] != 0 or (external_data[0][3] & 0xF) != 1:
        raise RuntimeError("external_global must be one undefined ELF object symbol")

    own_data = [s for s in symbols if s[0] == "own_global"]
    if len(own_data) != 1 or own_data[0][5] != data_index or own_data[0][2] != 4:
        raise RuntimeError("own_global must be one four-byte .data object")
    own_offset = data_section[4] + own_data[0][1]
    if struct.unpack_from("<I", data, own_offset)[0] != 7:
        raise RuntimeError("own_global initializer was not emitted as 7")

    external_long = [s for s in symbols if s[0] == "external_long_global"]
    if len(external_long) != 1 or external_long[0][5] != 0 or (external_long[0][3] & 0xF) != 1:
        raise RuntimeError("external_long_global must be one undefined ELF object symbol")

    own_long = [s for s in symbols if s[0] == "own_long_global"]
    if len(own_long) != 1 or own_long[0][5] != data_index or own_long[0][2] != 8 or own_long[0][1] % 8:
        raise RuntimeError("own_long_global must be one aligned eight-byte .data object")
    own_long_offset = data_section[4] + own_long[0][1]
    if struct.unpack_from("<Q", data, own_long_offset)[0] != 0x0102030405060708:
        raise RuntimeError("own_long_global initializer mismatch")

    own_double = [s for s in symbols if s[0] == "own_double_global"]
    if len(own_double) != 1 or own_double[0][5] != data_index or own_double[0][2] != 8 or own_double[0][1] % 8:
        raise RuntimeError("own_double_global must be one aligned eight-byte .data object")
    own_double_offset = data_section[4] + own_double[0][1]
    if struct.unpack_from("<Q", data, own_double_offset)[0] != 0x400C000000000000:
        raise RuntimeError("own_double_global initializer mismatch")

    call_targets = []
    got_targets = []
    for at in range(rel[4], rel[4] + rel[5], 8):
        offset, info = struct.unpack_from("<II", data, at)
        rtype = info & 0xFF
        symbol_number = info >> 8
        if symbol_number >= len(symbols):
            raise RuntimeError("relocation symbol index outside .symtab")
        target = symbols[symbol_number][0]
        if rtype == 28:
            call_targets.append(target)
        elif rtype == 96:
            got_targets.append(target)
        else:
            raise RuntimeError(f"unexpected ARM relocation type {rtype} at {offset:#x}")

    expected_calls = Counter({
        "add_int": 3,
        "sum5": 1,
        "add_float": 1,
        "external_twice": 1,
        "__aeabi_idiv": 1,
        "__aeabi_uidiv": 1,
        "__aeabi_idivmod": 1,
        "__aeabi_uidivmod": 1,
        "aligned_long": 1,
        "stacked_long": 1,
        "echo_double": 1,
        "__aeabi_ldivmod": 2,
        "__aeabi_uldivmod": 2,
        "__aeabi_llsl": 1,
        "__aeabi_lasr": 1,
        "__aeabi_llsr": 1,
    })
    if Counter(call_targets) != expected_calls:
        raise RuntimeError(f"unexpected R_ARM_CALL targets: {Counter(call_targets)}")

    expected_got_targets = {
        "own_global",
        "external_global",
        "own_long_global",
        "external_long_global",
        "own_double_global",
    }
    actual_got_targets = set(got_targets)
    if actual_got_targets != expected_got_targets:
        raise RuntimeError(
            f"unexpected R_ARM_GOT_PREL targets: {Counter(got_targets)}")

    if b"$a\x00" not in data or b"$t\x00" in data:
        raise RuntimeError("A32 mapping symbol missing or Thumb mapping symbol present")
    if b"aeabi\x00" not in data:
        raise RuntimeError(".ARM.attributes vendor block missing")

    # Tag_CPU_arch=v7, profile=A, ARM ISA used, Thumb not required,
    # VFPv3-D16, 8-byte stack needed/preserved, base PCS VFP args.
    tags = bytes([6, 10, 7, 65, 8, 1, 9, 0, 10, 4, 24, 1, 25, 1, 28, 0])
    if tags not in data:
        raise RuntimeError("expected AAPCS32/base-PCS ARM attributes not found")


def harness() -> str:
    return r"""
.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.arm
.data
.p2align 2
.global external_global
.type external_global,%object
external_global:
    .word 11
.size external_global,4

.p2align 3
.global external_long_global
.type external_long_global,%object
external_long_global:
    .quad 0x2233445566778899
.size external_long_global,8

.text

.global external_twice
.type external_twice,%function
external_twice:
    add r0, r0, r0
    bx lr

.global __aeabi_idiv
.type __aeabi_idiv,%function
__aeabi_idiv:
    mvn r2, #19
    cmp r0, r2
    bne .Lidiv_bad
    cmp r1, #6
    bne .Lidiv_bad
    mvn r0, #2
    bx lr
.Lidiv_bad:
    mov r0, #99
    bx lr

.global __aeabi_uidiv
.type __aeabi_uidiv,%function
__aeabi_uidiv:
    cmp r0, #20
    bne .Luidiv_bad
    cmp r1, #6
    bne .Luidiv_bad
    mov r0, #3
    bx lr
.Luidiv_bad:
    mov r0, #99
    bx lr

.global __aeabi_idivmod
.type __aeabi_idivmod,%function
__aeabi_idivmod:
    mvn r2, #19
    cmp r0, r2
    bne .Lidivmod_bad
    cmp r1, #6
    bne .Lidivmod_bad
    mvn r0, #2
    mvn r1, #1
    bx lr
.Lidivmod_bad:
    mov r0, #99
    mov r1, #99
    bx lr

.global __aeabi_uidivmod
.type __aeabi_uidivmod,%function
__aeabi_uidivmod:
    cmp r0, #20
    bne .Luidivmod_bad
    cmp r1, #6
    bne .Luidivmod_bad
    mov r0, #3
    mov r1, #2
    bx lr
.Luidivmod_bad:
    mov r0, #99
    mov r1, #99
    bx lr

.global __aeabi_ldivmod
.type __aeabi_ldivmod,%function
__aeabi_ldivmod:
    mvn r12, #19
    cmp r0, r12
    bne .Lldiv_bad
    mvn r12, #0
    cmp r1, r12
    bne .Lldiv_bad
    cmp r2, #6
    bne .Lldiv_bad
    cmp r3, #0
    bne .Lldiv_bad
    mvn r0, #2
    mvn r1, #0
    mvn r2, #1
    mvn r3, #0
    bx lr
.Lldiv_bad:
    mov r0, #99
    mov r1, #0
    mov r2, #99
    mov r3, #0
    bx lr

.global __aeabi_uldivmod
.type __aeabi_uldivmod,%function
__aeabi_uldivmod:
    cmp r0, #5
    bne .Luldiv_bad
    cmp r1, #2
    bne .Luldiv_bad
    cmp r2, #3
    bne .Luldiv_bad
    cmp r3, #0
    bne .Luldiv_bad
    movw r0, #0xaaac
    movt r0, #0xaaaa
    mov r1, #0
    mov r2, #1
    mov r3, #0
    bx lr
.Luldiv_bad:
    mov r0, #99
    mov r1, #0
    mov r2, #99
    mov r3, #0
    bx lr

.global __aeabi_llsl
.type __aeabi_llsl,%function
__aeabi_llsl:
    movw r12, #0x7788
    movt r12, #0x5566
    cmp r0, r12
    bne .Lllsl_bad
    movw r12, #0x3344
    movt r12, #0x1122
    cmp r1, r12
    bne .Lllsl_bad
    cmp r2, #4
    bne .Lllsl_bad
    movw r0, #0x1111
    movt r0, #0x1111
    movw r1, #0x2222
    movt r1, #0x2222
    bx lr
.Lllsl_bad:
    mov r0, #99
    mov r1, #0
    bx lr

.global __aeabi_lasr
.type __aeabi_lasr,%function
__aeabi_lasr:
    movw r12, #0x7788
    movt r12, #0x5566
    cmp r0, r12
    bne .Llasr_bad
    movw r12, #0x3344
    movt r12, #0x8122
    cmp r1, r12
    bne .Llasr_bad
    cmp r2, #5
    bne .Llasr_bad
    movw r0, #0x5555
    movt r0, #0x5555
    movw r1, #0xaaaa
    movt r1, #0xaaaa
    bx lr
.Llasr_bad:
    mov r0, #99
    mov r1, #0
    bx lr

.global __aeabi_llsr
.type __aeabi_llsr,%function
__aeabi_llsr:
    movw r12, #0x7788
    movt r12, #0x5566
    cmp r0, r12
    bne .Lllsr_bad
    movw r12, #0x3344
    movt r12, #0x8122
    cmp r1, r12
    bne .Lllsr_bad
    cmp r2, #6
    bne .Lllsr_bad
    movw r0, #0x6666
    movt r0, #0x6666
    movw r1, #0xbbbb
    movt r1, #0xbbbb
    bx lr
.Lllsr_bad:
    mov r0, #99
    mov r1, #0
    bx lr

.global _start
.type _start,%function
_start:
    mov r11, sp
    mov r10, #1

    mov r0, #7
    mov r1, #5
    bl add_int
    mov r10, #29
    cmp r0, #12
    bne fail
    mov r10, #30
    cmp sp, r11
    bne fail

    mov r10, #2
    sub sp, sp, #8
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #4
    mov r12, #5
    str r12, [sp]
    bl sum5
    add sp, sp, #8
    cmp r0, #15
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #3
    movw r0, #0x0000
    movt r0, #0x3fc0
    movw r1, #0x0000
    movt r1, #0x4010
    bl add_float
    movw r1, #0x0000
    movt r1, #0x4070
    cmp r0, r1
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #4
    sub sp, sp, #8
    movw r0, #0x0000
    movt r0, #0x3f80
    movw r1, #0x0000
    movt r1, #0x4000
    movw r2, #0x0000
    movt r2, #0x4040
    movw r3, #0x0000
    movt r3, #0x4080
    movw r12, #0x0000
    movt r12, #0x40a0
    str r12, [sp]
    bl fifth_float
    add sp, sp, #8
    movw r1, #0x0000
    movt r1, #0x40a0
    cmp r0, r1
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #5
    mov r0, #4
    bl choose
    cmp r0, #7
    bne fail

    mvn r0, #2
    bl choose
    mvn r1, #6
    cmp r0, r1
    bne fail

    mov r10, #6
    mov r0, #4
    bl call_internal
    cmp r0, #13
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #7
    mov r0, #4
    bl call_nested
    cmp r0, #7
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #8
    mov r0, #6
    bl call_external
    cmp r0, #12
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #9
    mov r0, #1
    bl call_sum5
    cmp r0, #15
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #10
    movw r0, #0x0000
    movt r0, #0x3fc0
    movw r1, #0x0000
    movt r1, #0x4010
    bl call_float
    movw r1, #0x0000
    movt r1, #0x4070
    cmp r0, r1
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #11
    mvn r0, #19
    mov r1, #6
    bl signed_div
    mvn r1, #2
    cmp r0, r1
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #20
    mov r1, #6
    bl unsigned_div
    cmp r0, #3
    bne fail
    cmp sp, r11
    bne fail

    mvn r0, #19
    mov r1, #6
    bl signed_mod
    mvn r1, #1
    cmp r0, r1
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #20
    mov r1, #6
    bl unsigned_mod
    cmp r0, #2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #12
    bl read_own_global
    cmp r0, #7
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #13
    mov r0, #13
    bl set_own_global
    cmp r0, #13
    bne fail
    bl read_own_global
    cmp r0, #13
    bne fail
    bl own_global_address
    ldr r0, [r0]
    cmp r0, #13
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #14
    bl read_external_global
    cmp r0, #11
    bne fail
    mov r0, #17
    bl set_external_global
    cmp r0, #17
    bne fail
    bl read_external_global
    cmp r0, #17
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #15
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    bl echo_long
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #16
    bl long_constant
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #17
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x400c
    bl echo_double
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x400c
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #18
    bl double_constant
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x400c
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #19
    sub sp, sp, #8
    mov r0, #1
    mov r1, #99
    movw r2, #0x7788
    movt r2, #0x5566
    movw r3, #0x3344
    movt r3, #0x1122
    mov r12, #3
    str r12, [sp]
    bl aligned_long
    add sp, sp, #8
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #20
    sub sp, sp, #8
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #99
    movw r12, #0x7788
    movt r12, #0x5566
    str r12, [sp]
    movw r12, #0x3344
    movt r12, #0x1122
    str r12, [sp, #4]
    bl stacked_long
    add sp, sp, #8
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #21
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    bl call_aligned_long
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #22
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    bl call_stacked_long
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #23
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x400c
    bl call_echo_double
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x400c
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #24
    bl read_own_long_global
    movw r2, #0x0708
    movt r2, #0x0506
    cmp r0, r2
    bne fail
    movw r2, #0x0304
    movt r2, #0x0102
    cmp r1, r2
    bne fail

    mov r10, #25
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    bl set_own_long_global
    bl read_own_long_global
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #26
    bl read_external_long_global
    movw r2, #0x8899
    movt r2, #0x6677
    cmp r0, r2
    bne fail
    movw r2, #0x4455
    movt r2, #0x2233
    cmp r1, r2
    bne fail

    mov r10, #27
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    bl set_external_long_global
    bl read_external_long_global
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail
    movw r2, #0x3344
    movt r2, #0x1122
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #28
    bl read_own_double_global
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x400c
    cmp r1, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #41
    mvn r0, #0
    mov r1, #1
    mov r2, #2
    mov r3, #0
    bl long_add
    cmp r0, #1
    bne fail
    cmp r1, #2
    bne fail

    mov r10, #42
    mov r0, #1
    mov r1, #2
    mov r2, #2
    mov r3, #0
    bl long_sub
    mvn r2, #0
    cmp r0, r2
    bne fail
    cmp r1, #1
    bne fail

    mov r10, #43
    mov r0, #2
    mov r1, #1
    mov r2, #3
    mov r3, #0
    bl long_mul
    cmp r0, #6
    bne fail
    cmp r1, #3
    bne fail

    mov r10, #44
    mvn r0, #19
    mvn r1, #0
    mov r2, #6
    mov r3, #0
    bl long_div
    mvn r2, #2
    cmp r0, r2
    bne fail
    mvn r2, #0
    cmp r1, r2
    bne fail

    mov r10, #45
    mvn r0, #19
    mvn r1, #0
    mov r2, #6
    mov r3, #0
    bl long_mod
    mvn r2, #1
    cmp r0, r2
    bne fail
    mvn r2, #0
    cmp r1, r2
    bne fail

    mov r10, #46
    mov r0, #5
    mov r1, #2
    mov r2, #3
    mov r3, #0
    bl ulong_div
    movw r2, #0xaaac
    movt r2, #0xaaaa
    cmp r0, r2
    bne fail
    cmp r1, #0
    bne fail

    mov r10, #47
    mov r0, #5
    mov r1, #2
    mov r2, #3
    mov r3, #0
    bl ulong_mod
    cmp r0, #1
    bne fail
    cmp r1, #0
    bne fail

    mov r10, #48
    mov r0, #0
    mov r1, #1
    bl long_neg
    cmp r0, #0
    bne fail
    mvn r2, #0
    cmp r1, r2
    bne fail

    mov r10, #49
    mvn r0, #0
    mvn r1, #0
    mov r2, #0
    mov r3, #0
    bl long_less
    cmp r0, #1
    bne fail

    mov r10, #50
    mov r0, #0
    mov r1, #1
    mvn r2, #0
    mov r3, #0
    bl ulong_greater
    cmp r0, #1
    bne fail

    mov r0, #0
    mov r1, #1
    bl long_truth
    cmp r0, #1
    bne fail
    mov r0, #0
    mov r1, #0
    bl long_truth
    cmp r0, #0
    bne fail

    mov r10, #51
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x3ff8
    mov r2, #0
    movw r3, #0x0000
    movt r3, #0x4002
    bl double_add
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x400e
    cmp r1, r2
    bne fail

    mov r10, #52
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x3ff8
    mov r2, #0
    movw r3, #0x0000
    movt r3, #0x4002
    bl double_sub
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0xbfe8
    cmp r1, r2
    bne fail

    mov r10, #53
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x3ff8
    mov r2, #0
    movw r3, #0x0000
    movt r3, #0x4002
    bl double_mul
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x400b
    cmp r1, r2
    bne fail

    mov r10, #54
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x4000
    mov r2, #0
    movw r3, #0x0000
    movt r3, #0x4010
    bl double_div
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0x3fe0
    cmp r1, r2
    bne fail

    mov r10, #55
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x3ff8
    bl double_neg
    cmp r0, #0
    bne fail
    movw r2, #0x0000
    movt r2, #0xbff8
    cmp r1, r2
    bne fail

    mov r10, #56
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x3ff8
    mov r2, #0
    movw r3, #0x0000
    movt r3, #0x4002
    bl double_less
    cmp r0, #1
    bne fail

    mov r10, #57
    mov r0, #0
    movw r1, #0x0000
    movt r1, #0x8000
    bl double_truth
    cmp r0, #0
    bne fail
    cmp sp, r11
    bne fail

    mov r10, #61
    mov r0, #3
    mov r1, #4
    bl shl32
    cmp r0, #48
    bne fail

    mov r10, #62
    mvn r0, #15
    mov r1, #2
    bl sar32
    mvn r1, #3
    cmp r0, r1
    bne fail

    mov r10, #63
    mov r0, #0x80000000
    mov r1, #1
    bl shr32
    mov r1, #0x40000000
    cmp r0, r1
    bne fail

    mov r10, #64
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    mov r2, #4
    bl shl64
    movw r2, #0x1111
    movt r2, #0x1111
    cmp r0, r2
    bne fail
    movw r2, #0x2222
    movt r2, #0x2222
    cmp r1, r2
    bne fail

    mov r10, #65
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x8122
    mov r2, #5
    bl sar64
    movw r2, #0x5555
    movt r2, #0x5555
    cmp r0, r2
    bne fail
    movw r2, #0xaaaa
    movt r2, #0xaaaa
    cmp r1, r2
    bne fail

    mov r10, #66
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x8122
    mov r2, #6
    bl shr64
    movw r2, #0x6666
    movt r2, #0x6666
    cmp r0, r2
    bne fail
    movw r2, #0xbbbb
    movt r2, #0xbbbb
    cmp r1, r2
    bne fail

    mov r10, #67
    mvn r0, #1
    bl widen_signed
    mvn r2, #1
    cmp r0, r2
    bne fail
    mvn r2, #0
    cmp r1, r2
    bne fail

    mov r10, #68
    mvn r0, #1
    bl widen_unsigned
    mvn r2, #1
    cmp r0, r2
    bne fail
    cmp r1, #0
    bne fail

    mov r10, #69
    movw r0, #0x7788
    movt r0, #0x5566
    movw r1, #0x3344
    movt r1, #0x1122
    bl narrow_signed
    movw r2, #0x7788
    movt r2, #0x5566
    cmp r0, r2
    bne fail

    mov r10, #70
    movw r0, #0x8899
    movt r0, #0x6677
    movw r1, #0x4455
    movt r1, #0x2233
    bl narrow_unsigned
    movw r2, #0x8899
    movt r2, #0x6677
    cmp r0, r2
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #0
    mov r7, #1
    svc #0
fail:
    mov r0, r10
    mov r7, #1
    svc #0
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--imports", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--clang", default="clang")
    parser.add_argument("--linker", default="ld.lld")
    parser.add_argument("--qemu", default="qemu-arm-static")
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    obj = out / "android-arm32-a32.o"

    run([
        str(Path(args.compiler).resolve()),
        "-target=armv7a-linux-androideabi21",
        "-betterC", "-c",
        f"-I{Path(args.imports).resolve()}",
        str(here / "smoke.d"),
        f"-of={obj}",
    ])
    check_elf(obj)

    asm = out / "harness.s"
    harness_obj = out / "harness.o"
    exe = out / "a32-smoke"
    asm.write_text(harness())
    run([
        args.clang, "--target=armv7a-linux-androideabi21",
        "-march=armv7-a", "-marm", "-mfpu=vfpv3-d16", "-mfloat-abi=softfp",
        "-c", str(asm), "-o", str(harness_obj),
    ])
    run([args.linker, "-m", "armelf_linux_eabi", "-e", "_start",
         str(harness_obj), str(obj), "-o", str(exe)])
    run([args.qemu, str(exe)])
    print("PASS: A32 scalar base PCS: calls, PIC globals, 32/64 arithmetic, shifts, casts, softfp float/double")


if __name__ == "__main__":
    main()
