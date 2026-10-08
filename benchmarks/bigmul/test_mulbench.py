#!/usr/bin/env python3
"""Deterministic arithmetic and smoke benchmark acceptance for mulbench.c.

Runs on hosts with Python 3 and a C11 compiler. Optional 'bc' checks are enabled
when bc is installed. All output assertions are made outside timed intervals.
"""
import csv
import io
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def build(out: Path, candidate: bool = False, sanitize: bool = False):
    cc = os.environ.get("CC", "cc")
    argv = [cc, "-O2", "-std=c11", "-D_POSIX_C_SOURCE=200809L", "-Wall", "-Wextra", "-Werror"]
    if sanitize:
        argv += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    if candidate:
        argv += ["-DHAVE_CANDIDATE"]
    argv += [str(HERE / "mulbench.c")]
    if candidate:
        argv += [str(HERE / "candidate.example.c")]
    argv += ["-o", str(out)]
    subprocess.run(argv, check=True, capture_output=True, text=True)


def cases():
    # Includes signed protocol acceptance; timed multiplication is unsigned.
    pairs = [(0, 0), (0, 1), (-1, 1), (-1, -1), (1, 1), (2, -7),
             (2**32 - 1, 2**32 - 1), (2**64 - 1, 2**64 - 1)]
    rng = random.Random(0x1C2026)
    for bits in (1, 2, 7, 8, 15, 16, 31, 32, 33, 63, 64, 65,
                 127, 128, 129, 255, 256, 257, 511, 512, 513,
                 1023, 1024, 1025, 2047, 2048, 4096, 8192):
        m = (1 << bits) - 1
        near = 1 << (bits - 1)
        alternating = (m // 3) | near
        sparse = near | 1
        p = rng.getrandbits(bits) | near
        q = rng.getrandbits(bits) | near
        pairs.extend([(m, m), (m, near + 1), (alternating, m),
                      (sparse, p), (p, q), (p, p)])
        if bits > 64:
            pairs.append((p, rng.getrandbits(max(1, bits // 16)) | 1))
    return pairs


def as_hex(n):
    return ("-" if n < 0 else "") + format(abs(n), "x")


def execute_pipe(binary: Path, pairs):
    input_text = "".join(f"{as_hex(a)} {as_hex(b)}\n" for a, b in pairs)
    run = subprocess.run([str(binary), "--pipe"], input=input_text,
                         text=True, capture_output=True, check=True, timeout=90)
    results = [int(line, 16) for line in run.stdout.splitlines()]
    assert len(results) == len(pairs), (len(results), len(pairs))
    return results


def bc_product(a, b):
    bc = shutil.which("bc")
    if not bc:
        return None
    # Assign obase before ibase; parse bc's multiline continuation.
    query = f"obase=16\nibase=16\n{as_hex(a).upper()}*{as_hex(b).upper()}\n"
    run = subprocess.run([bc], input=query, text=True,
                         capture_output=True, check=True, timeout=15)
    return int(run.stdout.replace("\\\n", "").strip(), 16)


class MultiplicationAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory(prefix="ick-mulbench-")
        cls.schoolbook = Path(cls.tempdir.name) / "schoolbook"
        cls.candidate = Path(cls.tempdir.name) / "candidate"
        build(cls.schoolbook)
        build(cls.candidate, candidate=True)

    @classmethod
    def tearDownClass(cls):
        cls.tempdir.cleanup()

    def test_schoolbook_exact(self):
        pairs = cases()
        self.assertEqual(execute_pipe(self.schoolbook, pairs), [a*b for a, b in pairs])

    def test_candidate_adapter_exact(self):
        pairs = cases()
        self.assertEqual(execute_pipe(self.candidate, pairs), [a*b for a, b in pairs])

    def test_bc_independent_oracle_when_installed(self):
        if not shutil.which("bc"):
            self.skipTest("bc not installed; Python's exact int still checks full corpus")
        for a, b in [(0, 17), (-7, 13), (2**32-1, 2**32-1),
                     (2**129-1, 2**127+1), (2**513-1, 2**255-19)]:
            self.assertEqual(bc_product(a, b), a*b)

    def test_benchmark_csv_schema_and_positive_time(self):
        run = subprocess.run([str(self.schoolbook), "--bench", "129", "3"],
                             text=True, capture_output=True, check=True, timeout=60)
        rows = list(csv.DictReader(io.StringIO(run.stdout)))
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(row["implementation"], "schoolbook")
            self.assertGreater(int(row["bits_a"]), 0)
            self.assertGreater(int(row["bits_b"]), 0)
            self.assertGreater(int(row["reps"]), 0)
            self.assertGreater(float(row["median_ns"]), 0)
            self.assertGreater(float(row["p90_ns"]), 0)

    def test_bad_protocol_input_rejected(self):
        run = subprocess.run([str(self.schoolbook), "--pipe"], input="xyz 42\n",
                             text=True, capture_output=True)
        self.assertNotEqual(run.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
