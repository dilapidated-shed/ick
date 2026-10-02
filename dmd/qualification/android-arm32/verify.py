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

    for required in [".text", ".rel.text", ".symtab", ".strtab", ".ARM.attributes"]:
        if required not in section_by_name:
            raise RuntimeError(f"missing ELF section {required}")

    text_index, _ = section_by_name[".text"]
    rel_index, rel = section_by_name[".rel.text"]
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

    relocation_targets = []
    for at in range(rel[4], rel[4] + rel[5], 8):
        offset, info = struct.unpack_from("<II", data, at)
        rtype = info & 0xFF
        symbol_number = info >> 8
        if rtype != 28:
            raise RuntimeError(f"unexpected ARM relocation type {rtype} at {offset:#x}")
        if symbol_number >= len(symbols):
            raise RuntimeError("relocation symbol index outside .symtab")
        relocation_targets.append(symbols[symbol_number][0])

    expected = Counter({"add_int": 3, "sum5": 1, "add_float": 1, "external_twice": 1})
    if Counter(relocation_targets) != expected:
        raise RuntimeError(f"unexpected R_ARM_CALL targets: {Counter(relocation_targets)}")

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
.text

.global external_twice
.type external_twice,%function
external_twice:
    add r0, r0, r0
    bx lr

.global _start
.type _start,%function
_start:
    mov r11, sp

    mov r0, #7
    mov r1, #5
    bl add_int
    cmp r0, #12
    bne fail
    cmp sp, r11
    bne fail

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

    mov r0, #4
    bl choose
    cmp r0, #7
    bne fail

    mvn r0, #2
    bl choose
    mvn r1, #6
    cmp r0, r1
    bne fail

    mov r0, #4
    bl call_internal
    cmp r0, #13
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #4
    bl call_nested
    cmp r0, #7
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #6
    bl call_external
    cmp r0, #12
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #1
    bl call_sum5
    cmp r0, #15
    bne fail
    cmp sp, r11
    bne fail

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

    mov r0, #0
    mov r7, #1
    svc #0
fail:
    mov r0, #1
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
    print("PASS: ELF32 EM_ARM A32, R_ARM_CALL, internal/external calls, base PCS softfp, r0-r3 + stack arguments")


if __name__ == "__main__":
    main()
