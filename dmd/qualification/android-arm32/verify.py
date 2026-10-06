#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import shutil
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

    text_index, text_section = section_by_name[".text"]
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

    for name, value, size, info, _, shndx in symbols:
        if shndx == text_index and (info & 0xF) == 2 and name == "add_int":
            start = text_section[4] + value
            words = [
                struct.unpack_from("<I", data, at)[0]
                for at in range(start, start + size, 4)
            ]
            print("add_int words:", " ".join(f"{word:08x}" for word in words))

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


def check_neon_elf(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise RuntimeError("NEON fixture is not an ELF object")
    e_type, e_machine = struct.unpack_from("<HH", data, 16)
    if (e_type, e_machine) != (1, 40):
        raise RuntimeError("NEON fixture is not ELF32 ARM")
    flags = struct.unpack_from("<I", data, 36)[0]
    if flags != 0x05000000:
        raise RuntimeError(f"NEON fixture escaped base PCS softfp: {flags:#x}")

    shoff = struct.unpack_from("<I", data, 32)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 46)
    sections = [
        struct.unpack_from("<IIIIIIIIII", data, shoff + i * shentsize)
        for i in range(shnum)
    ]
    shstr = sections[shstrndx]
    shstr_data = data[shstr[4]:shstr[4] + shstr[5]]

    def cstring(blob: bytes, offset: int) -> str:
        end = blob.find(b"\0", offset)
        if end < 0:
            raise RuntimeError("unterminated ELF string")
        return blob[offset:end].decode("ascii")

    by_name = {}
    for section in sections:
        name = cstring(shstr_data, section[0]) if section[0] else ""
        by_name[name] = section

    if ".text" not in by_name or ".ARM.attributes" not in by_name:
        raise RuntimeError("NEON fixture lacks required ELF sections")
    text_section = by_name[".text"]
    text = data[text_section[4]:text_section[4] + text_section[5]]
    if len(text) % 4:
        raise RuntimeError("A32 NEON text is not word aligned")
    words = struct.unpack("<" + "I" * (len(text) // 4), text)

    load_store_mask = 0xFFF01FFF
    operation_mask = 0xFFF11FF1

    def has(mask: int, value: int) -> bool:
        return any((word & mask) == value for word in words)

    required = [
        (load_store_mask, 0xF4200A8F, "VLD1.32 q"),
        (load_store_mask, 0xF4000A8F, "VST1.32 q"),
        (operation_mask, 0xF2000D40, "VADD.F32 q"),
        (operation_mask, 0xF2200D40, "VSUB.F32 q"),
        (operation_mask, 0xF3000D50, "VMUL.F32 q"),
    ]
    for mask, value, name in required:
        if not has(mask, value):
            raise RuntimeError(f"missing ARM32 NEON instruction family: {name}")

    if b"fft_butterfly4\0" not in data:
        raise RuntimeError("NEON fixture lost fft_butterfly4 symbol")

    neon_tags = bytes([6, 10, 7, 65, 8, 1, 9, 0, 10, 3, 12, 1,
                       24, 1, 25, 1, 28, 0])
    if neon_tags not in data:
        raise RuntimeError("expected ARMv7 VFPv3 + NEONv1 softfp attributes not found")

    rel = by_name.get(".rel.text")
    if rel is not None and rel[5] != 0:
        raise RuntimeError("NEON FFT fixture unexpectedly requires text relocations/calls")


def neon_harness() -> str:
    return r"""
.syntax unified
.arch armv7-a
.fpu neon
.arm

.data
.p2align 4
even_real:
    .space 16
even_imag:
    .space 16
odd_real:
    .space 16
odd_imag:
    .space 16

left_real:
    .float 10, 20, 30, 40
left_imag:
    .float 1, 2, 3, 4
right_real:
    .float 1, 2, 3, 4
right_imag:
    .float 5, 6, 7, 8
twiddle_real:
    .float 1, 0, -1, 0
twiddle_imag:
    .float 0, 1, 0, -1

expected:
    .float 11, 14, 27, 48
    .float 6, 4, -4, 0
    .float 9, 26, 33, 32
    .float -4, 0, 10, 8

.text
.global _start
.type _start,%function
_start:
    mov r11, sp
    sub sp, sp, #24

    ldr r0, =even_real
    ldr r1, =even_imag
    ldr r2, =odd_real
    ldr r3, =odd_imag

    ldr r12, =left_real
    str r12, [sp, #0]
    ldr r12, =left_imag
    str r12, [sp, #4]
    ldr r12, =right_real
    str r12, [sp, #8]
    ldr r12, =right_imag
    str r12, [sp, #12]
    ldr r12, =twiddle_real
    str r12, [sp, #16]
    ldr r12, =twiddle_imag
    str r12, [sp, #20]

    bl fft_butterfly4
    add sp, sp, #24
    cmp sp, r11
    bne fail

    ldr r0, =even_real
    ldr r1, =expected
    mov r2, #16
check:
    ldr r3, [r0], #4
    ldr r4, [r1], #4
    cmp r3, r4
    bne fail
    subs r2, r2, #1
    bne check

    mov r0, #0
    mov r7, #1
    svc #0

fail:
    mov r0, #1
    mov r7, #1
    svc #0
"""


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
    mov r10, #1
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


def elf32_sections(path: Path) -> tuple[bytes, dict[str, tuple[int, tuple[int, ...]]]]:
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
    if shentsize != 40 or shnum < 11 or shstrndx >= shnum:
        raise RuntimeError("unexpected ordinary-D ELF32 section table")
    sections = [
        struct.unpack_from("<IIIIIIIIII", data, shoff + i * shentsize)
        for i in range(shnum)
    ]
    shstr = sections[shstrndx]
    shstr_data = data[shstr[4]:shstr[4] + shstr[5]]

    def cstring(blob: bytes, offset: int) -> str:
        end = blob.find(b"\0", offset)
        if end < 0:
            raise RuntimeError("unterminated ELF string")
        return blob[offset:end].decode("ascii")

    by_name = {
        cstring(shstr_data, section[0]) if section[0] else "": (i, section)
        for i, section in enumerate(sections)
    }
    return data, by_name


def check_ordinary_d_elf(path: Path, module_name: str = "ordinary_d") -> None:
    data, sections = elf32_sections(path)
    required = [
        ".text", ".rel.text", ".data", ".symtab", ".strtab",
        ".ARM.attributes", "minfo", ".relminfo",
        ".group.d_dso", ".data.d_dso_rec", ".text.d_dso_init", ".rel.text.d_dso_init",
        ".init_array.d_dso_ctor", ".rel.init_array.d_dso_ctor",
        ".fini_array.d_dso_dtor", ".rel.fini_array.d_dso_dtor",
    ]
    for name in required:
        if name not in sections:
            raise RuntimeError(f"ordinary-D object is missing {name}")

    text_index, _ = sections[".text"]
    data_index, data_section = sections[".data"]
    sym_index, sym_section = sections[".symtab"]
    str_index, strings_section = sections[".strtab"]
    minfo_index, minfo_section = sections["minfo"]
    rel_minfo_index, rel_minfo_section = sections[".relminfo"]
    if sym_section[1] != 2 or sym_section[6] != str_index or sym_section[9] != 16:
        raise RuntimeError("ordinary-D symbol table linkage is malformed")
    if minfo_section[1] != 1 or minfo_section[2] != 3 or minfo_section[5] != 4:
        raise RuntimeError("ordinary-D minfo section is not writable 32-bit data")
    if (rel_minfo_section[1], rel_minfo_section[6], rel_minfo_section[7], rel_minfo_section[9]) != (
        9, sym_index, minfo_index, 8,
    ):
        raise RuntimeError("ordinary-D ModuleInfo relocation section is malformed")

    strings = data[strings_section[4]:strings_section[4] + strings_section[5]]

    def cstring(blob: bytes, offset: int) -> str:
        end = blob.find(b"\0", offset)
        if end < 0:
            raise RuntimeError("unterminated ELF string")
        return blob[offset:end].decode("ascii")

    symbols = []
    for at in range(sym_section[4], sym_section[4] + sym_section[5], 16):
        name_off, value, size = struct.unpack_from("<III", data, at)
        info, other, shndx = struct.unpack_from("<BBH", data, at + 12)
        symbols.append((cstring(strings, name_off) if name_off else "", value, size, info, other, shndx))

    by_symbol = {symbol[0]: (index, symbol) for index, symbol in enumerate(symbols) if symbol[0]}
    if module_name == "ordinary_d":
        ordinary = by_symbol.get("ordinary_d_add")
        if not ordinary or ordinary[1][5] != text_index or (ordinary[1][3] & 0xF) != 2:
            raise RuntimeError("ordinary-D scalar function is not an A32 text symbol")

    module_info_name = f"_D{len(module_name)}{module_name}12__ModuleInfoZ"
    module_info = by_symbol.get(module_info_name)
    if not module_info or module_info[1][5] != data_index or (module_info[1][3] & 0xF) != 1:
        raise RuntimeError("ordinary-D ModuleInfo is not a defined data symbol")
    _, (name, value, size, _, _, _) = module_info
    expected = struct.pack("<II", 0x1004, 0) + module_name.encode("ascii") + b"\0"
    if size != len(expected):
        raise RuntimeError(f"ordinary-D ModuleInfo size is {size}, expected {len(expected)}")
    payload_at = data_section[4] + value
    if data[payload_at:payload_at + size] != expected:
        raise RuntimeError("ordinary-D standalone ModuleInfo payload mismatch")

    if minfo_section[5] != 4 or struct.unpack_from("<I", data, minfo_section[4])[0] != 0:
        raise RuntimeError("ordinary-D minfo pointer must be a zero-addend relocation slot")
    if rel_minfo_section[5] != 8:
        raise RuntimeError("ordinary-D minfo must contain one pointer relocation")
    relocation_offset, relocation_info = struct.unpack_from("<II", data, rel_minfo_section[4])
    if relocation_offset != 0 or (relocation_info & 0xFF) != 2 or relocation_info >> 8 != module_info[0]:
        raise RuntimeError("ordinary-D minfo must reference its ModuleInfo with R_ARM_ABS32")

    if b"$a\0" not in data or b"$t\0" in data:
        raise RuntimeError("ordinary-D object escaped A32 mapping symbols")
    base_pcs_tags = bytes([6, 10, 7, 65, 8, 1, 9, 0, 10, 4, 24, 1, 25, 1, 28, 0])
    if base_pcs_tags not in data:
        raise RuntimeError("ordinary-D object lost AAPCS32 base-PCS softfp attributes")

    undefined = [name for name, _, _, _, _, shndx in symbols if name and shndx == 0]
    print("ordinary-D undefined symbols:", ", ".join(undefined) if undefined else "(none)")
    if sorted(undefined) != ["__start_minfo", "__stop_minfo", "_d_dso_registry"]:
        raise RuntimeError(f"ordinary-D runtime dependencies mismatch: {undefined}")
    for name in ["__start_minfo", "__stop_minfo"]:
        if by_symbol[name][1][3:5] != (0x10, 2):
            raise RuntimeError("minfo boundaries must be global hidden linker symbols")
    if by_symbol["_d_dso_registry"][1][3] != 0x12:
        raise RuntimeError("druntime registration must be a strong external function")

    group_index, group = sections[".group.d_dso"]
    grouped_names = [
        ".data.d_dso_rec", ".text.d_dso_init", ".rel.text.d_dso_init",
        ".init_array.d_dso_ctor", ".rel.init_array.d_dso_ctor",
        ".fini_array.d_dso_dtor", ".rel.fini_array.d_dso_dtor",
    ]
    expected_group = [1] + [sections[name][0] for name in grouped_names]
    if (group[1], group[6], group[7], group[8], group[9]) != (
        17, sym_index, by_symbol[".data.d_dso_rec"][0], 4, 4,
    ) or list(struct.unpack_from("<8I", data, group[4])) != expected_group:
        raise RuntimeError("ordinary-D registration COMDAT group is malformed")
    for name in grouped_names:
        if not sections[name][1][2] & 0x200:
            raise RuntimeError(f"registration section {name} is not grouped")

    def relocations(name: str, target: str) -> list[tuple[int, str, int]]:
        _, section = sections[name]
        if (section[1], section[6], section[7], section[9]) != (
            9, sym_index, sections[target][0], 8,
        ):
            raise RuntimeError(f"malformed relocation section {name}")
        result = []
        for at in range(section[4], section[4] + section[5], 8):
            offset, info = struct.unpack_from("<II", data, at)
            result.append((offset, symbols[info >> 8][0], info & 255))
        return result

    if relocations(".rel.text.d_dso_init", ".text.d_dso_init") != [
        (56, "_d_dso_registry", 28), (68, ".data.d_dso_rec", 3),
        (72, "__start_minfo", 3), (76, "__stop_minfo", 3),
    ]:
        raise RuntimeError("registration must use a druntime call and PC-relative address literals")
    _, thunk = sections[".text.d_dso_init"]
    if thunk[2] != 0x206 or thunk[5] != 80 or thunk[8] != 4:
        raise RuntimeError("registration thunk is not word-aligned grouped A32 code")
    instructions = struct.unpack_from("<20I", data, thunk[4])
    if instructions[:4] != (0xE92D4010, 0xE24DD010, 0xE3A00001, 0xE58D0000) or \
            instructions[13:17] != (0xE1A0000D, 0xEBFFFFFE, 0xE28DD010, 0xE8BD8010):
        raise RuntimeError("registration thunk lost its aligned stack/CompilerDSOData frame")
    for prefix, kind in [("init", 14), ("fini", 15)]:
        name = f".{prefix}_array.d_dso_{'ctor' if prefix == 'init' else 'dtor'}"
        _, section = sections[name]
        if (section[1], section[2], section[5], section[8]) != (kind, 0x203, 4, 4) or \
                struct.unpack_from("<I", data, section[4])[0] != 0 or \
                relocations(".rel" + name, name) != [(0, "__d_dso_init", 2)]:
            raise RuntimeError(f"malformed ordinary-D loader hook {name}")
    print("ordinary-D runtime reference: minfo R_ARM_ABS32 ->", module_info_name)


def check_ordinary_d_boundary(compiler: Path, imports: Path, here: Path, out: Path,
                              clang: str, linker: str, qemu: str) -> None:
    ordinary_obj = out / "ordinary-d-arm32.o"
    run([
        str(compiler),
        "-target=armv7a-linux-androideabi21",
        "-c",
        f"-I{imports}",
        str(here / "ordinary_d.d"),
        f"-of={ordinary_obj}",
    ])
    check_ordinary_d_elf(ordinary_obj)

    empty_obj = out / "ordinary-d-empty.o"
    run([str(compiler), "-target=armv7a-linux-androideabi21", "-c", f"-I{imports}",
         str(here / "ordinary_d_empty.d"), f"-of={empty_obj}"])
    check_ordinary_d_elf(empty_obj, "ordinary_d_empty")

    rows = []
    for fixture, diagnostic, requirement, blocker in [
        ("ordinary_d_empty", None, "ModuleInfo; _d_dso_registry; __start_minfo; __stop_minfo",
         "matching Android ARM32 druntime body providing _d_dso_registry; no Android runtime link qualified"),
        ("ordinary_d", None, "ModuleInfo; _d_dso_registry; __start_minfo; __stop_minfo",
         "matching Android ARM32 druntime body providing _d_dso_registry; no Android runtime link qualified"),
        ("ordinary_d_linkage", "top-level extern(C) functions only", "D function ABI/name mangling",
         "qualify D linkage/calling convention before admitting ordinary D-linkage functions"),
        ("ordinary_d_assert", "unsupported expression", "assert runtime call and source-file D slice",
         "represent D slices/source data and lower assert to the matching druntime entrypoint"),
        ("ordinary_d_static_ctor", "ordinary-D ModuleInfo with lifecycle/import data is not implemented",
         "ModuleInfo lifecycle callback relocation", "emit exact lifecycle/import ModuleInfo fields and callbacks"),
    ]:
        common = [str(compiler), "-target=armv7a-linux-androideabi21", "-c", f"-I{imports}",
                  str(here / (fixture + ".d"))]
        # Separate actual frontend success from reaching/rejection by the object backend.
        run(common + ["-o-"])
        if diagnostic:
            rejected_obj = out / (fixture + ".o")
            rejected_obj.write_bytes(b"stale ordinary-D output must not survive")
            command = common + [f"-of={rejected_obj}"]
            print("+", " ".join(command))
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=60)
            print(result.stdout, end="")
            if result.returncode == 0 or rejected_obj.exists() or \
                    "A32 backend:" not in result.stdout or diagnostic not in result.stdout:
                raise RuntimeError(f"{fixture} did not fail closed at the expected ARM32 boundary")
        rows.append("\t".join([fixture, "PASS", "REACHED", "NONE" if diagnostic else "PASS",
                               "not emitted: " + requirement if diagnostic else requirement,
                               "FAIL_CLOSED" if diagnostic else "SUPPORTED", blocker]))

    harness_obj = out / "ordinary-d-registry-harness.o"
    run([clang, "--target=armv7a-linux-androideabi21", "-march=armv7-a", "-marm",
         "-mfloat-abi=softfp", "-c", str(here / "ordinary_d_registry_harness.s"), "-o", str(harness_obj)])
    executable = out / "ordinary-d-registry-oracle"
    run([linker, "-m", "armelf_linux_eabi", "-e", "_start", str(harness_obj),
         str(ordinary_obj), str(empty_obj), "-o", str(executable)])
    run([qemu, str(executable)])
    # Linking with -z text proves the registration thunk does not need dynamic text relocations.
    run([linker, "-m", "armelf_linux_eabi", "-shared", "-z", "text", str(ordinary_obj),
         str(empty_obj), "-o", str(out / "ordinary-d-boundary.so")])

    receipt = out / "ordinary-d-boundary.tsv"
    receipt.write_text(
        "construct\tparse_semantic\tarm32_backend\telf_object\truntime_references\tbackend_support\tnext_blocker\n"
        + "\n".join(rows) + "\n"
    )
    inspection = subprocess.run(
        ["readelf", "-h", "-SW", "-sW", "-rW", "-g", "-A", str(ordinary_obj)],
        check=True, stdout=subprocess.PIPE, text=True, timeout=60)
    (out / "ordinary-d-readelf.txt").write_text(inspection.stdout)
    print(inspection.stdout, end="")
    (out / "ordinary-d-provenance.txt").write_text(
        "target=armv7a-linux-androideabi21\nflags=-c (no -betterC)\n"
        f"compiler_sha256={hashlib.sha256(compiler.read_bytes()).hexdigest()}\n"
        f"object_sha256={hashlib.sha256(ordinary_obj.read_bytes()).hexdigest()}\n"
        "runtime_link=NOT_QUALIFIED\nphysical_device_execution=NOT_RUN\n")
    print("PASS: ordinary-D ARM32 ModuleInfo and explicit druntime registration dependency")
    print("PASS: two-module COMDAT registration ABI oracle (not Android druntime), PIC link")
    print("PASS: ordinary-D unsupported constructs fail closed without stale output")


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

    check_ordinary_d_boundary(
        Path(args.compiler).resolve(), Path(args.imports).resolve(), here, out,
        args.clang, args.linker, args.qemu)

    neon_obj = out / "android-arm32-neon-fft.o"
    run([
        str(Path(args.compiler).resolve()),
        "-target=armv7a-linux-androideabi21",
        "-betterC", "-c",
        f"-I{Path(args.imports).resolve()}",
        str(here / "neon_fft.d"),
        f"-of={neon_obj}",
    ])
    check_neon_elf(neon_obj)

    neon_asm = out / "neon-harness.s"
    neon_harness_obj = out / "neon-harness.o"
    neon_exe = out / "a32-neon-fft"
    neon_asm.write_text(neon_harness())
    run([
        args.clang, "--target=armv7a-linux-androideabi21",
        "-march=armv7-a", "-marm", "-mfpu=neon", "-mfloat-abi=softfp",
        "-c", str(neon_asm), "-o", str(neon_harness_obj),
    ])
    run([args.linker, "-m", "armelf_linux_eabi", "-e", "_start",
         str(neon_harness_obj), str(neon_obj), "-o", str(neon_exe)])
    run([args.qemu, "-cpu", "cortex-a9", str(neon_exe)])

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

    # Mutate a separate copy of the fixture so the assembly harness must reject
    # a compiler-produced zero result from add_int at its first result check.
    smoke_source = here / "smoke.d"
    mutant_source = out / "smoke-add-int-zero-mutant.d"
    mutant_obj = out / "android-arm32-a32-add-int-zero-mutant.o"
    mutant_exe = out / "a32-smoke-add-int-zero-mutant"
    shutil.copyfile(smoke_source, mutant_source)
    original = mutant_source.read_text()
    mutation = "extern(C) int add_int(int a, int b)\n{\n    return a + b;\n}\n"
    if original.count(mutation) != 1:
        raise RuntimeError("could not isolate the first add_int result in smoke.d")
    mutant_source.write_text(original.replace(
        mutation,
        "extern(C) int add_int(int a, int b)\n{\n    return 0;\n}\n",
        1,
    ))

    run([
        str(Path(args.compiler).resolve()),
        "-target=armv7a-linux-androideabi21",
        "-betterC", "-c",
        f"-I{Path(args.imports).resolve()}",
        str(mutant_source),
        f"-of={mutant_obj}",
    ])
    check_elf(mutant_obj)
    run([args.linker, "-m", "armelf_linux_eabi", "-e", "_start",
         str(harness_obj), str(mutant_obj), "-o", str(mutant_exe)])
    mutant_command = [args.qemu, str(mutant_exe)]
    print("+", " ".join(mutant_command))
    mutant = subprocess.run(mutant_command, check=False, timeout=60)
    if mutant.returncode != 1:
        raise RuntimeError(
            "add_int-zero mutant must fail at stage 1; "
            f"got process status {mutant.returncode}"
        )

    print("PASS: scalar A32 harness rejects the add_int-zero mutant at failure stage 1")
    print("PASS: A32 scalar base PCS: calls, PIC globals, 32/64 arithmetic, shifts, casts, softfp float/double")
    print("PASS: ARMv7 NEON float4 FFT butterfly: vector ELF attributes, Q-register instruction families, and qemu execution")


if __name__ == "__main__":
    main()
