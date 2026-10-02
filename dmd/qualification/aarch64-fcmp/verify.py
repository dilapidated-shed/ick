#!/usr/bin/env python3
import argparse
import subprocess
from pathlib import Path

HARNESS = r"""
.text
.p2align 2
.global _start
.type _start,%function
_start:
    // 1.0 < 2.0: <, <=, !=
    mov     w19, #1
    movz    w0, #0x0000
    movk    w0, #0x3f80, lsl #16
    fmov    s0, w0
    movz    w1, #0x0000
    movk    w1, #0x4000, lsl #16
    fmov    s1, w1
    bl      comparison_mask
    cmp     w0, #11
    b.ne    fail

    // 2.0 > 1.0: !=, >, >=
    mov     w19, #2
    movz    w0, #0x0000
    movk    w0, #0x4000, lsl #16
    fmov    s0, w0
    movz    w1, #0x0000
    movk    w1, #0x3f80, lsl #16
    fmov    s1, w1
    bl      comparison_mask
    cmp     w0, #56
    b.ne    fail

    // Equal finite values: <=, ==, >=
    mov     w19, #3
    movz    w0, #0x0000
    movk    w0, #0x3f80, lsl #16
    fmov    s0, w0
    fmov    s1, w0
    bl      comparison_mask
    cmp     w0, #38
    b.ne    fail

    // NaN compared with finite: only != is true.
    mov     w19, #4
    movz    w0, #0x0000
    movk    w0, #0x7fc0, lsl #16
    fmov    s0, w0
    movz    w1, #0x0000
    movk    w1, #0x3f80, lsl #16
    fmov    s1, w1
    bl      comparison_mask
    cmp     w0, #8
    b.ne    fail

    // Finite compared with NaN: still only !=.
    mov     w19, #5
    movz    w0, #0x0000
    movk    w0, #0x3f80, lsl #16
    fmov    s0, w0
    movz    w1, #0x0000
    movk    w1, #0x7fc0, lsl #16
    fmov    s1, w1
    bl      comparison_mask
    cmp     w0, #8
    b.ne    fail

    // +0 and -0 compare equal.
    mov     w19, #6
    fmov    s0, wzr
    movz    w1, #0x0000
    movk    w1, #0x8000, lsl #16
    fmov    s1, w1
    bl      comparison_mask
    cmp     w0, #38
    b.ne    fail

    mov     w0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     w0, w19
    mov     x8, #93
    svc     #0
.size _start, .-_start
.section .note.GNU-stack,"",%progbits
"""

def run(command):
    print("+", " ".join(map(str, command)), flush=True)
    subprocess.run(command, check=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--imports", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--clang", default="clang")
    parser.add_argument("--linker", default="ld.lld")
    parser.add_argument("--qemu", default="qemu-aarch64-static")
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)

    obj = out / "fcmp.o"
    run([
        str(Path(args.compiler).resolve()),
        "-arm", "-betterC", "-c",
        f"-I{Path(args.imports).resolve()}",
        str(here / "compare.d"),
        f"-of={obj}",
    ])

    asm = out / "harness.s"
    harness_obj = out / "harness.o"
    exe = out / "fcmp-regression"
    asm.write_text(HARNESS)

    run([
        args.clang, "--target=aarch64-linux-gnu",
        "-c", str(asm), "-o", str(harness_obj),
    ])
    run([
        args.linker, "-m", "aarch64elf", "-e", "_start",
        str(harness_obj), str(obj), "-o", str(exe),
    ])
    run([args.qemu, str(exe)])
    print("PASS: AArch64 floating comparisons preserve source order and unordered-NaN semantics")

if __name__ == "__main__":
    main()
