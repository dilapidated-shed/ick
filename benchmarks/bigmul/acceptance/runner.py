#!/usr/bin/env python3
"""Explicit provider selection. Arithmetic equality does not prove provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from test_mulbench import as_hex, cases


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class Refusal(ValueError):
    pass


def resolve_executable(value):
    resolved = shutil.which(value)
    if not resolved:
        raise Refusal(f"executable unavailable: {value}")
    return Path(resolved).resolve()


def validate_identity(identity, executable):
    if not isinstance(identity, dict):
        raise Refusal("identity must be an object")
    if identity.get("binary_sha256") != digest(executable):
        raise Refusal("selected executable hash does not match identity")
    if identity.get("role") not in ("candidate", "baseline", "smoke"):
        raise Refusal("missing explicit provider role")
    if not identity.get("provider") or not identity.get("profile"):
        raise Refusal("missing provider/profile identity")
    if identity.get("whole_product_delegate") not in (None, False):
        raise Refusal("disallowed whole-product oracle delegation")
    if identity["role"] == "candidate":
        sources = identity.get("sources", {})
        if not sources:
            raise Refusal("candidate requires inspectable source hashes")
        for path, expected in sources.items():
            if digest(path) != expected:
                raise Refusal(f"source identity changed: {path}")
            text = Path(path).read_text(encoding="utf-8")
            if Path(path).name == "candidate.example.c" or re.search(
                    r"\b(?:mul_schoolbook|__gmp\w*|mpz_\w*|system|popen)\s*\(", text):
                raise Refusal("candidate source contains a forbidden delegate/control")
    # This refuses known/direct delegation. A reviewed source/link/stage receipt
    # is still required for paper-path acceptance (MB16); obfuscation, external
    # libraries and a dishonest manifest are outside this lexical check's proof.


def build_provider(source, executable, compiler, flags, role, provider, profile):
    source, executable = Path(source).resolve(), Path(executable).resolve()
    compiler = resolve_executable(compiler)
    if not source.is_file():
        raise Refusal("candidate source is unavailable")
    argv = [str(compiler), *flags, "-DHAVE_CANDIDATE", str(ROOT / "mulbench.c"),
            str(source), "-o", str(executable)]
    result = subprocess.run(argv, capture_output=True, text=True, timeout=120)
    receipt = {"argv": argv, "compiler_sha256": digest(compiler),
               "flags": flags, "stdout": result.stdout, "stderr": result.stderr,
               "status": result.returncode}
    if result.returncode:
        raise Refusal(json.dumps({"build_failure": receipt}))
    identity = {"role": role, "provider": provider, "profile": profile,
                "binary_sha256": digest(executable),
                "sources": {str(source): digest(source)},
                "harness_sha256": digest(ROOT / "mulbench.c"), "build": receipt}
    validate_identity(identity, executable)
    return identity


def execute(executable, identity, pairs, timeout=90):
    executable = Path(executable).resolve()
    validate_identity(identity, executable)
    payload = "".join(f"{as_hex(a)} {as_hex(b)}\n" for a, b in pairs).encode("ascii")
    try:
        result = subprocess.run([str(executable), "--pipe"], input=payload,
                                capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise Refusal(f"provider timeout; stdout={error.stdout!r}; stderr={error.stderr!r}") from error
    if result.returncode:
        raise Refusal(f"provider exit {result.returncode}; stdout={result.stdout!r}; stderr={result.stderr!r}")
    lines = result.stdout.splitlines()
    if len(lines) != len(pairs):
        raise Refusal(f"output count {len(lines)} != request count {len(pairs)}")
    for index, (line, (a, b)) in enumerate(zip(lines, pairs)):
        if not re.fullmatch(rb"-?[0-9a-fA-F]+", line):
            raise Refusal(f"invalid result syntax at request {index}")
        if int(line, 16) != a * b:
            raise Refusal(f"wrong product at request {index}")
    return {"status": "PASS", "provider": identity, "cases": len(pairs),
            "input_sha256": hashlib.sha256(payload).hexdigest(),
            "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
            "stderr": result.stderr.decode("utf-8", errors="replace"),
            "argv": [str(executable), "--pipe"], "exit_status": result.returncode}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--candidate-source", type=Path)
    selection.add_argument("--binary", type=Path)
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--output-binary", type=Path)
    parser.add_argument("--compiler", default="cc")
    parser.add_argument("--compiler-flag", action="append", default=[])
    parser.add_argument("--role", choices=("candidate", "baseline", "smoke"), default="candidate")
    parser.add_argument("--provider", default="explicit-candidate")
    parser.add_argument("--profile", default="unsigned-limb32-v1")
    parser.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()
    try:
        if args.timeout <= 0 or args.timeout > 120:
            raise Refusal("timeout must be in (0,120]")
        if args.candidate_source:
            if not args.output_binary:
                raise Refusal("source selection requires --output-binary")
            flags = args.compiler_flag or ["-O2", "-std=c11", "-D_POSIX_C_SOURCE=200809L"]
            identity = build_provider(args.candidate_source, args.output_binary,
                                      args.compiler, flags, args.role, args.provider, args.profile)
            binary = args.output_binary
        else:
            if not args.identity:
                raise Refusal("prebuilt selection requires --identity")
            identity = json.loads(args.identity.read_text(encoding="utf-8"))
            binary = args.binary
        receipt = execute(binary, identity, cases(), args.timeout)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error)}))
        return 1
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
