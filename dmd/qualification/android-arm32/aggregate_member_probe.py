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

positive = here / "aggregate_static_member.d"
positive_obj = out / "aggregate-static-member.o"
run([
    compiler, "-conf=", f"-target={TARGET}", "-c", f"-I{imports}",
    positive, f"-of={positive_obj}",
])

inspection = run(["readelf", "-h", "-sW", "-rW", "-A", positive_obj]).stdout
(out / "aggregate-static-member-readelf.txt").write_text(inspection)
if "Machine:                           ARM" not in inspection:
    raise RuntimeError("aggregate fixture is not an ARM object")
if not any(re.search(r"\bFUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+aggregate_static_add$", line)
           for line in inspection.splitlines()):
    raise RuntimeError("static struct method was not emitted as one global function")
for field in ("left", "present", "wide"):
    if any(line.rstrip().endswith(" " + field) for line in inspection.splitlines()):
        raise RuntimeError(f"layout-only field escaped as an ELF symbol: {field}")

harness_obj = out / "aggregate-static-member-harness.o"
run([
    args.clang, f"--target={TARGET}", "-march=armv7-a", "-marm",
    "-mfpu=vfpv3-d16", "-mfloat-abi=softfp", "-c",
    here / "aggregate_static_member_harness.s", "-o", harness_obj,
])
executable = out / "aggregate-static-member-oracle"
run([
    args.linker, "-m", "armelf_linux_eabi", "-e", "_start",
    harness_obj, positive_obj, "-o", executable,
])
execution = run([args.qemu, executable], check=False)
(out / "aggregate-static-member-execution.log").write_text(execution.stdout)
if execution.returncode != 0:
    raise RuntimeError(f"static struct method oracle returned {execution.returncode}")

negative = here / "aggregate_instance_member.d"
common = [compiler, "-conf=", f"-target={TARGET}", "-c", f"-I{imports}", negative]
run(common + ["-o-"])
negative_obj = out / "aggregate-instance-member.o"
negative_obj.write_bytes(b"stale output must not survive")
rejected = run(common + [f"-of={negative_obj}"], check=False)
(out / "aggregate-instance-member.log").write_text(rejected.stdout)
if rejected.returncode == 0 or negative_obj.exists():
    raise RuntimeError("instance member did not fail closed")
if "A32 backend:" not in rejected.stdout or "top-level or static-struct" not in rejected.stdout:
    raise RuntimeError("instance member failed outside the qualified hidden-context boundary")

(out / "aggregate-member-provenance.txt").write_text(
    f"target={TARGET}\n"
    f"compiler_sha256={digest(compiler)}\n"
    f"positive_source_sha256={digest(positive)}\n"
    f"positive_object_sha256={digest(positive_obj)}\n"
    f"harness_sha256={digest(here / 'aggregate_static_member_harness.s')}\n"
    f"executable_sha256={digest(executable)}\n"
    "layout_fields=NO_ELF_SYMBOLS\n"
    "static_struct_method=EXECUTED_UNDER_QEMU\n"
    "instance_method=FAIL_CLOSED_NO_OBJECT\n"
    "android_runtime_link=NOT_QUALIFIED\n"
    "physical_device_execution=NOT_RUN\n"
)
print("PASS: struct layout fields remain type-only; static member executes; instance member fails closed")
