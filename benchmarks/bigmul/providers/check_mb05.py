#!/usr/bin/env python3
"""MB05 comparison controls. Host compilers are never qualified ICK evidence."""
import argparse
import csv
import ctypes
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path[:0] = [str(ROOT / "acceptance"), str(ROOT / "corpus")]
from runner import as_hex, digest, execute, cases, resolve_executable
from corpus import encode, generate, require, validate, validate_legacy, value

FLAGS = ["-O2", "-std=c11", "-D_POSIX_C_SOURCE=200809L", "-Wall", "-Wextra", "-Werror"]
FUNCTIONS = {"schoolbook": "mul_schoolbook", "karatsuba32-bounded": "mb05_karatsuba32",
             "gmp-mpn-mul": "mb05_gmp32", "gmp-mpn-sqr": "mb05_gmp_square32"}
WORD = ctypes.c_uint32
POINTER = ctypes.POINTER(WORD)


def words(number, count=None):
    number = abs(number)
    count = count or max(1, (number.bit_length()+31)//32)
    return [(number >> (32*i)) & 0xffffffff for i in range(count)]


def legacy_pairs():
    validate_legacy()
    pairs = []
    for line in (ROOT/"corpus/mul-v1.tsv").read_text(encoding="ascii").splitlines():
        if not line.startswith("#"):
            fields = line.split("\t")
            pairs.append((int(fields[4]), int(fields[5])))
    return pairs


def checked(function, left, right):
    """Full words, different prefills, guards and source snapshots, not hashes alone."""
    a, b = (WORD * len(left))(*left), (WORD * len(right))(*right)
    expected = sum(x << (32*i) for i, x in enumerate(left)) * sum(x << (32*i) for i, x in enumerate(right))
    count = len(left)+len(right)
    wanted = words(expected, count)
    for prefill in (0xa5a5a5a5, 0x5a5a5a5a):
        out = (WORD * (count+2))(*([prefill]*(count+2)))
        pointer = ctypes.cast(ctypes.byref(out, ctypes.sizeof(WORD)), POINTER)
        status = function(a, len(a), b, len(b), pointer)
        require(status == 0, f"provider refused supported shape {len(a)}/{len(b)}: {status}")
        require(list(a) == left and list(b) == right, "provider changed an input")
        require(out[0] == prefill and out[count+1] == prefill, "provider wrote outside output")
        require(list(out)[1:-1] == wanted, "wrong/missing output word (including high zeroes)")
    return expected


def worker(binary, provider, corpus):
    library = ctypes.CDLL(str(binary))
    function = getattr(library, FUNCTIONS[provider])
    function.argtypes = [POINTER, ctypes.c_size_t, POINTER, ctypes.c_size_t, POINTER]
    function.restype = ctypes.c_int
    square = provider == "gmp-mpn-sqr"
    with corpus.open("rb") as stream:
        rows = validate(stream)
    hashes, inputs = hashlib.sha256(), hashlib.sha256()
    tested = 0
    for row in rows:
        left = words(value(row, "left"), int(row["left_limbs"]))
        right = left[:] if square else words(value(row, "right"), int(row["right_limbs"]))
        product = checked(function, left, right)
        inputs.update((str(len(left))+":"+str(len(right))+":"+
                       "".join(f"{word:08x}" for word in left+right)+"\n").encode("ascii"))
        hashes.update(f"{row['case_sha256']}\t{product:x}\n".encode("ascii"))
        tested += 1
    # The immutable legacy corpus includes every byte pair and its original
    # larger fixtures. The square route explicitly maps each left operand.
    legacy = legacy_pairs()
    for a, b in legacy:
        if square: b = a
        product = checked(function, words(a), words(b))
        hashes.update(f"legacy\t{a}\t{b}\t{product:x}\n".encode("ascii"))
        tested += 1
    # Both signs of the Karatsuba difference term, carry chains and recursion
    # boundaries, odd widths, same-value distinct buffers, padded zero arrays.
    for length in (15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 129, 257, 513, 2048):
        patterns = ([0]*length, [0xffffffff]*length,
                    [0xffffffff if i % 2 else 1 for i in range(length)],
                    [1]+[0]*(length-1))
        for index, left in enumerate(patterns):
            right = left[:] if square else list(reversed(patterns[(index+1) % len(patterns)]))
            checked(function, left, right)
            tested += 1
    probe = (WORD * 4)(1, 2, 3, 4)
    for a, na, b, nb, out in [(None, 1, probe, 1, probe), (probe, 0, probe, 1, probe),
                               (probe, 1, None, 1, probe), (probe, 1, probe, 0, probe),
                               (probe, 1, probe, 1, None)]:
        require(function(a, na, b, nb, out) != 0, "invalid pointers/lengths admitted")
    if provider != "schoolbook":
        require(function(probe, 2049, probe, 1, probe) != 0, "bounded provider admitted excess width")
    if square:
        other = (WORD * 4)(2, 2, 3, 4)
        require(function(probe, 4, other, 4, probe) != 0, "square admitted unequal values")
    print(json.dumps({"status": "PASS", "provider": provider, "direct_cases": tested,
                      "corpus_cases": len(rows), "corpus_sha256": digest(corpus), "legacy_cases": len(legacy),
                      "input_mapping": "square of each left operand" if square else "unmodified magnitudes and stored lengths",
                      "effective_input_sha256": inputs.hexdigest(),
                      "ordered_products_sha256": hashes.hexdigest(), "binary_sha256": digest(binary)}))
    return 0


def run(argv, commands, **kwargs):
    try:
        result = subprocess.run([str(x) for x in argv], capture_output=True, text=True,
                                timeout=120, **kwargs)
    except subprocess.TimeoutExpired as error:
        commands.append({"argv": [str(x) for x in argv], "status": "TIMEOUT",
                         "stdout": str(error.stdout), "stderr": str(error.stderr)})
        raise
    commands.append({"argv": result.args, "status": result.returncode,
                     "stdout": result.stdout, "stderr": result.stderr})
    return result


def gmp_samples(binary, mode, square, rows, commands):
    requests = []
    for row in rows:
        a = words(value(row, "left"), int(row["left_limbs"]))
        b = a[:] if square else words(value(row, "right"), int(row["right_limbs"]))
        requests.append((a, b))
    payload = "".join(" ".join(map(str, [len(a), len(b), *a, *b]))+"\n" for a, b in requests)
    operation = "square" if square else "multiply"
    result = run([binary, mode, operation], commands, input=payload)
    require(result.returncode == 0, "GMP sample process failed")
    samples = list(csv.DictReader(io.StringIO(result.stdout), delimiter="\t"))
    require(len(samples) == 3*len(requests), "missing/extra native samples")
    for index, sample in enumerate(samples):
        case, trial = divmod(index, 3)
        require((int(sample["case"]), int(sample["trial"])) == (case, trial), "sample order mismatch")
        require(sample["mode"] == mode and sample["operation"] == operation, "sample identity mismatch")
        require(int(sample["repetitions"]) == 8 and int(sample["elapsed_ns"]) > 0, "invalid raw timing")
        a, b = requests[case]
        expected = sum(x << (32*i) for i, x in enumerate(a)) * sum(x << (32*i) for i, x in enumerate(b))
        require(len(sample["product_hex"]) == 8*(len(a)+len(b)), "missing high output zeroes")
        require(int(sample["product_hex"], 16) == expected, "sample product differs from independent oracle")
    return {"mode": mode, "operation": operation, "request_sha256": hashlib.sha256(payload.encode()).hexdigest(),
            "case_sha256": [row["case_sha256"] for row in rows], "raw_samples": samples,
            "timer": "CLOCK_MONOTONIC", "units": "ns per eight-call batch", "calibrated": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-missing-gmp", action="store_true")
    parser.add_argument("--gmp-include", type=Path)
    parser.add_argument("--gmp-library", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--worker", nargs=3, metavar=("BINARY", "PROVIDER", "CORPUS"))
    args = parser.parse_args()
    if args.worker:
        return worker(Path(args.worker[0]), args.worker[1], Path(args.worker[2]))
    compiler = resolve_executable(os.environ.get("CC", "cc"))
    commands, outcomes, samples, refused = [], [], [], []
    report = {"job": "MB05", "status": "FAIL", "architecture": platform.machine(),
              "compiler_lane": "host C control; qualified ICK NOT_RUN",
              "compiler": {"path": str(compiler), "sha256": digest(compiler), "flags": FLAGS},
              "sources": {str(p.relative_to(ROOT)): digest(p) for p in [HERE/"providers.h", HERE/"karatsuba.c",
                          HERE/"gmp.c", HERE/"gmp_fixture.c", Path(__file__), ROOT/"mulbench.c", ROOT/"timing/engine.c"]},
              "providers": outcomes, "samples": samples, "mutants_rejected": refused, "commands": commands}
    try:
        validate_legacy()
        version = run([compiler, "--version"], commands)
        require(version.returncode == 0, "compiler identification failed")
        with tempfile.TemporaryDirectory(prefix="ick-mb05-") as temporary:
            folder = Path(temporary)
            corpus = folder / "medium-v2.tsv"
            corpus.write_bytes(encode(generate("medium")))
            report["inputs"] = {"medium_v2_sha256": digest(corpus), "smoke_v2_sha256": digest(ROOT/"corpus/smoke-v2.tsv"),
                                "legacy_v1_sha256": digest(ROOT/"corpus/mul-v1.tsv")}
            with corpus.open("rb") as stream:
                rows = validate(stream)
            pair_corpus = [(value(row, "left"), value(row, "right")) for row in rows] + legacy_pairs()
            flags = list(FLAGS)
            include_flags = ["-I", str(args.gmp_include.resolve())] if args.gmp_include else []
            link_flags = [str(args.gmp_library.resolve())] if args.gmp_library else ["-lgmp"]
            # The actual compiler/header/link probe decides availability.
            probe = run([compiler, *flags, *include_flags, "-M", HERE/"gmp.c"], commands)
            gmp_available = probe.returncode == 0
            if gmp_available:
                fixture = folder / "gmp-fixture"
                built = run([compiler, *flags, *include_flags, HERE/"gmp.c", HERE/"gmp_fixture.c",
                             ROOT/"timing/engine.c", *link_flags, "-o", fixture], commands)
                require(built.returncode == 0, "GMP header present but build/link failed")
                metadata = run([fixture, "--metadata"], commands)
                require(metadata.returncode == 0, "GMP metadata failed")
                config = json.loads(metadata.stdout)
                require(config["gmp_version"] == config["header_version"], "GMP runtime/header version mismatch")
                require(config["gmp_version"] == "6.3.0", "this adapter qualification pins GMP 6.3.0")
                require(config["numb_bits"] in (32, 64) and config["nail_bits"] == 0, "unsupported GMP configuration")
                require(config["runtime_limb_bits"] == 8*config["limb_bytes"], "GMP limb ABI mismatch")
                linkage = run(["ldd", fixture], commands)
                require(linkage.returncode == 0, "cannot identify GMP runtime linkage")
                match = re.search(r"libgmp[^\s]*\s+=>\s+(/\S+)", linkage.stdout)
                require(match is not None, "GMP dynamic library identity absent")
                library = Path(match.group(1)).resolve()
                dependencies = probe.stdout.replace("\\\n", " ").split()
                headers = [Path(path).resolve() for path in dependencies if path.endswith("/gmp.h")]
                require(len(headers) == 1 and headers[0].is_file(), "GMP header identity absent")
                config.update({"status": "PASS", "linkage": "dynamic", "library_path": str(library),
                               "library_sha256": digest(library), "header_sha256": digest(headers[0]),
                               "original_build_configuration": "UNKNOWN: no original config.log; observed ABI fingerprint below",
                               "license": "LGPLv3+ OR GPLv2+", "license_url": "https://gmplib.org/manual/Copying",
                               "contract_url": "https://gmplib.org/manual/Low_002dlevel-Functions"})
                config["configuration_sha256"] = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()
                if shutil.which("dpkg-query"):
                    package = run(["dpkg-query", "-W", "libgmp10", "libgmp-dev"], commands)
                    config["package_query"] = {"status": package.returncode, "stdout": package.stdout, "stderr": package.stderr}
                report["gmp"] = config
            else:
                report["gmp"] = {"status": "NOT_RUN", "reason": "development header unavailable", "coverage": 0}
                require(args.allow_missing_gmp, "required GMP header unavailable; optional omission must be explicit")
            providers = ["schoolbook", "karatsuba32-bounded"] + (["gmp-mpn-mul", "gmp-mpn-sqr"] if gmp_available else [])
            for provider in providers:
                is_gmp = provider.startswith("gmp-")
                sources = [ROOT/"mulbench.c"]
                if provider == "karatsuba32-bounded": sources.append(HERE/"karatsuba.c")
                if is_gmp: sources.append(HERE/"gmp.c")
                binary = folder / (provider+".so")
                build = run([compiler, *flags, *(include_flags if is_gmp else []), "-fPIC", "-shared",
                             "-Dmain=mb05_unused_main", *sources, *(link_flags if is_gmp else []), "-o", binary], commands)
                require(build.returncode == 0, f"provider build failed: {provider}")
                result = run([sys.executable, Path(__file__), "--worker", binary, provider, corpus], commands)
                require(result.returncode == 0, f"provider direct acceptance failed: {provider}")
                receipt = json.loads(result.stdout)
                require(receipt["status"] == "PASS" and receipt["corpus_sha256"] == digest(corpus), "worker receipt mismatch")
                if provider != "gmp-mpn-sqr":
                    protocol = folder / provider
                    extra = ["-DHAVE_CANDIDATE", "-DMB05_EXPORT_CANDIDATE"] if provider != "schoolbook" else []
                    built = run([compiler, *flags, *(include_flags if is_gmp else []), *extra, *sources,
                                 *(link_flags if is_gmp else []), "-o", protocol], commands)
                    require(built.returncode == 0, "protocol provider build failed")
                    identity = {"role": "baseline", "provider": provider, "profile": "unsigned-limb32-v1",
                                "binary_sha256": digest(protocol)}
                    receipt["protocol"] = execute(protocol, identity, pair_corpus+cases())
                    sanitized = folder / (provider+"-sanitized")
                    sanitizer = run([compiler, *flags, *(include_flags if is_gmp else []), *extra,
                                     "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-no-pie",
                                     *sources, *(link_flags if is_gmp else []), "-o", sanitized], commands)
                    require(sanitizer.returncode == 0, "required host sanitizer build failed")
                    payload = "".join(f"{as_hex(a)} {as_hex(b)}\n" for a, b in pair_corpus+cases())
                    environment = dict(os.environ)
                    checked_run = run([sanitized, "--pipe"], commands, input=payload, env=environment)
                    leak_status = "runtime available; comprehensive leak acceptance not claimed"
                    if checked_run.returncode and "LeakSanitizer has encountered a fatal error" in checked_run.stderr:
                        environment["ASAN_OPTIONS"] = "detect_leaks=0"
                        leak_status = "NOT_RUN: runtime process inspection failed; retained probe and disabled leak detector only"
                        checked_run = run([sanitized, "--pipe"], commands, input=payload, env=environment)
                    require(checked_run.returncode == 0, "sanitized provider process failed")
                    lines = checked_run.stdout.splitlines()
                    require(len(lines) == len(pair_corpus+cases()), "sanitizer output count mismatch")
                    require(all(re.fullmatch(r"-?[0-9a-fA-F]+", line) and int(line,16) == a*b
                                for line, (a,b) in zip(lines, pair_corpus+cases())), "sanitizer product mismatch")
                    receipt["address_undefined_sanitizers"] = "PASS"
                    receipt["leak_sanitizer"] = leak_status
                outcomes.append(receipt)
            products = [r["ordered_products_sha256"] for r in outcomes if r["provider"] != "gmp-mpn-sqr"]
            require(len(set(products)) == 1, "providers did not use identical products/operand bytes")
            if gmp_available:
                # No whole-input generation, packing, checking or export in
                # native timing. Adapter32 includes allocation and conversions.
                selected = [row for row in rows if row["family"] in ("ones", "imbalance", "storage", "small")]
                for square in (False, True):
                    for mode in ("native", "adapter32"):
                        samples.append(gmp_samples(fixture, mode, square, selected, commands))
                if report["gmp"]["numb_bits"] == 64:
                    mutant = folder / "gmp-bad-pack.so"
                    built = run([compiler, *flags, *include_flags, "-fPIC", "-shared", "-DMB05_DROP_HIGH_HALF",
                                 HERE/"gmp.c", *link_flags, "-o", mutant], commands)
                    require(built.returncode == 0, "repacking mutant failed to build")
                    result = run([sys.executable, Path(__file__), "--worker", mutant, "gmp-mpn-mul", corpus], commands)
                    require(result.returncode != 0 and "wrong/missing output word" in result.stderr,
                            "high-half mutant did not fail the outer worker on an arithmetic mismatch")
                    refused.append({"name": "drop-high-half", "status": "EXPECTED_REFUSAL", "binary_sha256": digest(mutant),
                                    "exit_status": result.returncode})
                else:
                    refused.append({"name": "drop-high-half", "status": "NOT_APPLICABLE: GMP has 32-bit data limbs"})
            report["status"] = "PASS" if gmp_available else "PASS_WITHOUT_OPTIONAL_GMP"
            report["scope"] = "bounded conventional comparison providers; no paper-path, ICK or physical acceptance"
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    text = json.dumps(report, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text+"\n", encoding="utf-8")
    print(text)
    return 0 if report["status"].startswith("PASS") else 1


if __name__ == "__main__":
    sys.exit(main())
