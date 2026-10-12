#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from trace import case_hash, require, validate

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    compiler = shutil.which(os.environ.get("CC", "cc"))
    require(compiler is not None, "host control compiler unavailable")
    commands, traces = [], []
    source = ROOT / "schoolbook_trace.c"
    with tempfile.TemporaryDirectory(prefix="mb17-") as temporary:
        folder = Path(temporary)
        traced, plain = folder / "traced", folder / "plain"
        for path, input_source in ((traced, source), (plain, ROOT.parent / "mulbench.c")):
            argv = [compiler, "-O2", "-std=c11", "-D_POSIX_C_SOURCE=200809L",
                    "-Wall", "-Wextra", "-Werror", str(input_source), "-o", str(path)]
            run = subprocess.run(argv, capture_output=True, text=True, timeout=60)
            require(run.returncode == 0, run.stderr)
            commands.append({"argv": argv, "status": run.returncode, "stderr": run.stderr})
        for a, b in (([0], [0]), ([0xffffffff], [0xffffffff]),
                     ([0xffffffff, 0xffffffff], [0xffffffff, 0xffffffff]), ([1, 0, 2], [3, 4])):
            argv = [str(traced), digest(source), digest(traced), case_hash(a, b),
                    str(len(a)), str(len(b)), *(str(value) for value in a+b)]
            start = time.perf_counter_ns()
            run = subprocess.run(argv, capture_output=True, text=True, timeout=10)
            traced_endpoint_ns = time.perf_counter_ns()-start
            require(run.returncode == 0, run.stderr)
            parsed = validate(run.stdout, digest(source), digest(traced), a, b)
            left, right = sum(v << (32*i) for i,v in enumerate(a)), sum(v << (32*i) for i,v in enumerate(b))
            start = time.perf_counter_ns()
            baseline = subprocess.run([str(plain), "--pipe"], input=f"{left:x} {right:x}\n",
                                      capture_output=True, text=True, timeout=10)
            plain_endpoint_ns = time.perf_counter_ns()-start
            require(baseline.returncode == 0 and int(baseline.stdout,16) == parsed["output"], "trace/plain mismatch")
            traces.append({"argv": argv, "source_sha256": digest(source), "binary_sha256": digest(traced),
                           "left_limbs": a, "right_limbs": b, "raw_trace": run.stdout,
                           "plain_binary_sha256": digest(plain), "plain_stdout": baseline.stdout,
                           "trace_endpoint_ns": traced_endpoint_ns, "plain_endpoint_ns": plain_endpoint_ns})
        mutations = {
            "wrong-executable": run.stdout.replace(digest(traced), "0"*64, 1),
            "bad-reference": run.stdout.replace("\t-\t32\tvalue", "\t999999\t32\tvalue", 1),
            "unsupported-units": run.stdout.replace("\t32\tvalue", "\t32\tbytes", 1),
            "dropped-event": "\n".join(run.stdout.splitlines()[:10] + run.stdout.splitlines()[11:])+"\n",
            "duplicate-sequence": run.stdout.replace("\n1\t", "\n0\t", 1),
            "incomplete": run.stdout.replace("complete\t1", "complete\t0", 1),
        }
        rejected = []
        for name, text in mutations.items():
            try:
                validate(text, digest(source), digest(traced), a, b)
            except (ValueError, IndexError):
                rejected.append(name)
            else:
                raise ValueError(f"trace defect passed: {name}")
    print(json.dumps({"job": "MB17", "status": "PASS", "scope": "executed schoolbook control",
                      "recursive_control": "NOT_RUN: no retained recursive provider established",
                      "paper_candidate": "NOT_RUN: waits for MB16",
                      "commands": commands, "traces": traces, "mutants_rejected": rejected}))


if __name__ == "__main__":
    main()
