#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, subprocess
from pathlib import Path
PIN = "74917954b53f7f35b13e61b4438c7253834929ed"
TARGET = "armv7a-linux-androideabi21"
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(c, check=True):
    print("+", " ".join(map(str, c)), flush=True)
    return subprocess.run(list(map(str, c)), check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
p = argparse.ArgumentParser()
p.add_argument("--compiler", required=True)
p.add_argument("--runtime", required=True)
p.add_argument("--output", required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[3]
rt = Path(a.runtime).resolve()
out = Path(a.output).resolve()
out.mkdir(parents=True, exist_ok=True)
if run(["git", "-C", rt, "rev-parse", "HEAD"]).stdout.strip() != PIN:
    raise RuntimeError("runtime pin mismatch")
vals = {}
for line in (root / "dmd/RUNTIME.lock").read_text().splitlines():
    k, s, v = line.partition("=")
    if s:
        vals[k] = v
cfg = rt / "druntime/src/core/stdc/config.d"
ov = root / "dmd/qualification/android-arm32/runtime-config-arm32.patch"
if sha(cfg) != vals["android_arm32_config_original_sha256"] or sha(ov) != vals["android_arm32_config_overlay_sha256"]:
    raise RuntimeError("overlay input mismatch")
run(["git", "-C", rt, "apply", "--check", ov])
run(["git", "-C", rt, "apply", ov])
if sha(cfg) != vals["android_arm32_config_result_sha256"]:
    raise RuntimeError("overlay result mismatch")
imp = rt / "druntime/import"
src = rt / "druntime/src"
front = run([a.compiler, "-conf=", f"-target={TARGET}", "-c", "-o-",
             f"-I{imp}", f"-I{src}", root / "dmd/qualification/android-arm32/runtime_frontend_abi.d"], False)
(out / "runtime-frontend-abi.log").write_text(front.stdout)
if front.returncode:
    print(front.stdout, end="")
    raise RuntimeError("frontend ABI fixture failed")
obj = out / "sections-elf-shared.o"
obj.write_bytes(b"stale")
result = run([a.compiler, "-conf=", f"-target={TARGET}", "-c", f"-I{imp}", f"-I{src}",
              src / "rt/sections_elf_shared.d", f"-of={obj}"], False)
(out / "runtime-provider.log").write_text(result.stdout)
if result.returncode == 0 or obj.exists():
    raise RuntimeError("provider did not fail closed")
for bad in ("c_long_double needs to be declared", "must be a va_list parameter", "must have a va_list parameter"):
    if bad in result.stdout:
        raise RuntimeError("repaired frontend diagnostic returned: " + bad)
diagnostics = [line for line in result.stdout.splitlines() if "A32 backend:" in line]
if not diagnostics:
    print(result.stdout, end="")
    raise RuntimeError("provider did not reach A32 backend")
first = diagnostics[0]
(out / "runtime-provider-first-diagnostic.txt").write_text(first + "\n")
(out / "runtime-provider-provenance.txt").write_text(
    f"runtime_commit={PIN}\ntarget={TARGET}\ncompiler_sha256={sha(Path(a.compiler))}\n"
    f"provider_sha256={sha(src / 'rt/sections_elf_shared.d')}\nfrontend_abi=PASS\n"
    f"provider_backend=REACHED_FAIL_CLOSED\nfirst_backend_diagnostic={first}\n"
    "android_runtime_link=NOT_QUALIFIED\nphysical_device_execution=NOT_RUN\n")
print("PASS: matching runtime frontend ABI reaches the A32 backend")
print(first)
