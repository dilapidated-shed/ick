#!/usr/bin/env python3
import csv
import hashlib
import io
import json
import math
import os
import re
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def quantile(values, probability):
    require(values and 0 <= probability <= 1, "invalid quantile")
    ordered = sorted(values)
    return ordered[max(0, math.ceil(probability * len(ordered)) - 1)]


def validate_rows(rows, expected):
    require(len(rows) == 6, "missing raw trials")
    for trial, row in enumerate(rows):
        require(int(row["trial"]) == trial, "trial order")
        require(int(row["wall_ns"]) > 0 and int(row["cpu_ns"]) >= 0, "timer failure")
        require(int(row["repetitions"]) == int(row["calls"]) > 0, "elided callback")
        output = sum(int(row[f"out{k}"]) << (32 * k) for k in range(4))
        require(output == expected, "arithmetic elided or wrong output")


def main():
    compiler = shutil.which(os.environ.get("CC", "cc"))
    require(compiler is not None, "C control compiler unavailable")
    commands, runs = [], []
    def execute(argv):
        result = subprocess.run(argv, capture_output=True, text=True, timeout=60)
        commands.append({"argv": argv, "status": result.returncode,
                         "stdout": result.stdout, "stderr": result.stderr})
        require(result.returncode == 0, f"command failed: {commands[-1]}")
        return result
    with tempfile.TemporaryDirectory(prefix="mb06-") as temporary:
        folder = Path(temporary)
        flags = ["-O3", "-std=c11", "-D_POSIX_C_SOURCE=200809L", "-Wall", "-Wextra", "-Werror"]
        fake = folder / "fake-clock"
        execute([compiler, *flags, str(ROOT / "engine.c"), str(ROOT / "fake_clock.c"), "-o", str(fake)])
        execute([str(fake)])
        # Unit mutation is applied to the real engine, checked by exact fake-clock values.
        mutated = folder / "units.c"
        mutated.write_text((ROOT / "engine.c").read_text().replace("seconds * UINT64_C(1000000000)", "seconds * UINT64_C(1000000)"))
        execute([compiler, *flags, "-I", str(ROOT), str(mutated), str(ROOT / "fake_clock.c"), "-o", str(fake)])
        bad_units = subprocess.run([str(fake)], capture_output=True, timeout=5)
        require(bad_units.returncode != 0, "swapped timing units passed")
        arithmetic = folder / "arithmetic.o"
        execute([compiler, *flags, "-fno-lto", "-Dmain=unused_benchmark_main", "-c",
                 str(ROOT.parent / "mulbench.c"), "-o", str(arithmetic)])
        for lto in (False, True):
            binary = folder / ("fixture-lto" if lto else "fixture")
            execute([compiler, *flags, *(["-flto"] if lto else []), str(ROOT / "engine.c"),
                     str(ROOT / "fixture.c"), str(arithmetic), "-o", str(binary)])
            symbols = execute(["objdump", "-d", str(binary)]).stdout
            require(re.search(r"\b(?:call|jmp|bl|b)\s+[^\n]*<mul_schoolbook>", symbols) is not None,
                    "opaque arithmetic call absent from optimized host binary")
            for numbers in ([1, 2, 3, 4], [0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff]):
                for mode in ("arithmetic", "control"):
                    argv = [str(binary), *(str(n) for n in numbers), mode]
                    run = execute(argv)
                    rows = list(csv.DictReader(io.StringIO(run.stdout), delimiter="\t"))
                    a, b = numbers[0] + (numbers[1] << 32), numbers[2] + (numbers[3] << 32)
                    validate_rows(rows, a if mode == "control" else a * b)
                    runs.append({"lto": lto, "mode": mode, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                                 "argv": argv, "raw_tsv": run.stdout})
        binary = folder / "elided"
        execute([compiler, *flags, "-DELIDE_ARITHMETIC", str(ROOT / "engine.c"), str(ROOT / "fixture.c"),
                 str(arithmetic), "-o", str(binary)])
        run = execute([str(binary), "1", "2", "3", "4", "arithmetic"])
        try:
            validate_rows(list(csv.DictReader(io.StringIO(run.stdout), delimiter="\t")), (1+(2<<32))*(3+(4<<32)))
        except ValueError:
            pass
        else:
            raise ValueError("elided arithmetic accepted")
    require(statistics.median([1, 3, 5, 7]) == 4 and quantile([1, 3, 5, 7], .9) == 7,
            "median/nearest-rank batch quantile convention")
    # Large disassembly is checked, but not embedded into the summary.
    commands = [row for row in commands if row["argv"][0] != "objdump"]
    print(json.dumps({"job": "MB06", "status": "PASS", "scope": "standalone host timing engine",
                      "mutants_rejected": ["nanoseconds-to-microseconds", "elided-arithmetic"],
                      "compiler": compiler, "commands": commands, "raw_runs": runs}))


if __name__ == "__main__":
    main()
