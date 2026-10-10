#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

TARGET = "armv7a-linux-androideabi21"


def run(command, check=True):
    command = [str(item) for item in command]
    print("+", " ".join(command), flush=True)
    result = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    if check and result.returncode:
        print(result.stdout, end="")
        raise subprocess.CalledProcessError(result.returncode, command, output=result.stdout)
    return result


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


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
compiler = Path(args.compiler).resolve()
imports = Path(args.imports).resolve()

source = here / "delegate_transport.d"
d_object = out / "delegate-transport.o"
run([
    compiler, "-conf=", f"-target={TARGET}", "-c", f"-I{imports}",
    source, f"-of={d_object}",
])

inspection = run(["readelf", "-h", "-sW", "-rW", "-A", d_object]).stdout
(out / "delegate-transport-readelf.txt").write_text(inspection)
if "Machine:                           ARM" not in inspection:
    raise RuntimeError("delegate transport fixture is not an ARM object")
for symbol in ("delegate_transport_register_forward", "delegate_transport_stack_forward"):
    if not any(re.search(r"\bFUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+" + symbol + r"$", line)
               for line in inspection.splitlines()):
        raise RuntimeError(f"missing delegate transport function: {symbol}")

c_object = out / "delegate-transport-reference.o"
run([
    args.clang, f"--target={TARGET}", "-march=armv7-a", "-marm",
    "-mfloat-abi=softfp", "-O2", "-ffreestanding", "-fno-builtin",
    "-fno-stack-protector", "-fno-unwind-tables", "-fno-asynchronous-unwind-tables",
    "-c", here / "delegate_transport_reference.c", "-o", c_object,
])

harness_object = out / "delegate-transport-harness.o"
run([
    args.clang, f"--target={TARGET}", "-march=armv7-a", "-marm",
    "-mfpu=vfpv3-d16", "-mfloat-abi=softfp", "-c",
    here / "delegate_transport_harness.s", "-o", harness_object,
])

executable = out / "delegate-transport-oracle"
run([
    args.linker, "-m", "armelf_linux_eabi", "-e", "_start",
    harness_object, c_object, d_object, "-o", executable,
])
execution = run([args.qemu, executable], check=False)
(out / "delegate-transport-execution.log").write_text(execution.stdout)
if execution.returncode != 0:
    raise RuntimeError(f"delegate transport oracle returned {execution.returncode}")

negative = here / "delegate_split_rejected.d"
common = [compiler, "-conf=", f"-target={TARGET}", "-c", f"-I{imports}", negative]
run(common + ["-o-"])
negative_object = out / "delegate-split-rejected.o"
negative_object.write_bytes(b"stale output must not survive")
rejected = run(common + [f"-of={negative_object}"], check=False)
(out / "delegate-split-rejected.log").write_text(rejected.stdout)
if rejected.returncode == 0 or negative_object.exists():
    raise RuntimeError("r3/stack delegate split did not fail closed")
if "A32 backend:" not in rejected.stdout or "split between r3 and the stack" not in rejected.stdout:
    print(rejected.stdout, end="")
    raise RuntimeError("delegate split failed outside the qualified transport boundary")

(out / "delegate-transport-provenance.txt").write_text(
    f"target={TARGET}\n"
    f"compiler_sha256={digest(compiler)}\n"
    f"d_source_sha256={digest(source)}\n"
    f"d_object_sha256={digest(d_object)}\n"
    f"c_reference_sha256={digest(here / 'delegate_transport_reference.c')}\n"
    f"c_object_sha256={digest(c_object)}\n"
    f"harness_sha256={digest(here / 'delegate_transport_harness.s')}\n"
    f"executable_sha256={digest(executable)}\n"
    "delegate_layout=context_then_function_pointer\n"
    "register_transport=r1_r2_after_one_word\n"
    "stack_transport=sp_plus_0_sp_plus_4\n"
    "r3_stack_split=FAIL_CLOSED_NO_OBJECT\n"
    "delegate_invocation=NOT_QUALIFIED\n"
    "delegate_return=NOT_QUALIFIED\n"
    "delegate_memory=NOT_QUALIFIED\n"
    "android_runtime_link=NOT_QUALIFIED\n"
    "physical_device_execution=NOT_RUN\n"
)
print("PASS: delegate values agree with the AAPCS32 two-pointer transport oracle")
