#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
import subprocess
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
    shentsize, shnum = struct.unpack_from("<HH", data, 46)
    if shentsize != 40 or shnum < 7:
        raise RuntimeError("unexpected ELF32 section table")

    # The emitter fixes .symtab at section 2. Global function values must be
    # word-aligned and must not carry the Thumb low-bit marker.
    sym = shoff + 2 * shentsize
    symoff = struct.unpack_from("<I", data, sym + 16)[0]
    symsize = struct.unpack_from("<I", data, sym + 20)[0]
    syment = struct.unpack_from("<I", data, sym + 36)[0]
    if syment != 16 or symsize < 48:
        raise RuntimeError("unexpected ARM32 symbol table")
    for at in range(symoff + 32, symoff + symsize, 16):
        value = struct.unpack_from("<I", data, at + 4)[0]
        if value & 3:
            raise RuntimeError(f"A32 function symbol is not word aligned: {value:#x}")

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
    print("PASS: ELF32 EM_ARM A32, EABI5/base PCS softfp, r0-r3 + stack arguments, binary32 VFP arithmetic")


if __name__ == "__main__":
    main()
