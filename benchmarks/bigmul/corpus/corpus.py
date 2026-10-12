#!/usr/bin/env python3
"""Versioned, per-case deterministic 32-bit little-endian operand records."""
import argparse
import hashlib
import io
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
PIN = "96e5ce0181dc92b269e444bc63c8f63684c56ad476474094b193ce4cd474f5f3"
VERSION = "limb32-corpus-v2"
FIELDS = ("id semantics family parameters seed square left_sign left_bits left_limbs "
          "left_bytes right_sign right_bits right_limbs right_bytes case_sha256").split()
BUDGETS = {"smoke": 129, "medium": 4097, "large": 16385}
MASK = (1 << 64) - 1


def require(condition, message):
    if not condition:
        raise ValueError(message)


def splitmix(state):
    state = (state + 0x9e3779b97f4a7c15) & MASK
    result = state
    result = ((result ^ (result >> 30)) * 0xbf58476d1ce4e5b9) & MASK
    result = ((result ^ (result >> 27)) * 0x94d049bb133111eb) & MASK
    return state, (result ^ (result >> 31)) & MASK


def random_value(bits, seed):
    state, value = seed, 0
    for offset in range(0, bits, 64):
        state, word = splitmix(state)
        value |= word << offset
    return (value & ((1 << bits) - 1)) | (1 << (bits - 1))


def operand(value, extra_limbs=0):
    magnitude = abs(value)
    limbs = max(1, (magnitude.bit_length() + 31) // 32) + extra_limbs
    return [str((value > 0) - (value < 0)), str(magnitude.bit_length()), str(limbs),
            magnitude.to_bytes(4 * limbs, "little").hex()]


def record(case_id, left, right, family, parameters, seed=0, square="general", extra_left=0):
    semantics = "signed-wrapper" if left < 0 or right < 0 else "unsigned-kernel"
    values = [case_id, semantics, family, parameters, f"{seed:016x}", square,
              *operand(left, extra_left), *operand(right)]
    values.append(hashlib.sha256("\t".join(values).encode("ascii")).hexdigest())
    return dict(zip(FIELDS, values))


def generate(budget="smoke", reverse=False):
    require(budget in BUDGETS, "unknown budget")
    rows = [record(f"v2/small/{a}/{b}", a, b, "small", f"a={a},b={b}")
            for a, b in [(0, 0), (0, 1), (1, 1), (-1, 1), (-1, -1), (2, -7)]]
    rows.append(record("v2/storage/leading-zero", 1, 2, "storage", "extra_left=2", extra_left=2))
    sizes = [1, 2, 7, 8, 15, 16]
    for center in (32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384):
        sizes.extend((center - 1, center, center + 1))
    for bits in sorted(set(sizes)):
        if bits > BUDGETS[budget]:
            continue
        top, mask = 1 << (bits - 1), (1 << bits) - 1
        for instance in range(3):
            case_id = f"v2/random/{bits}/{instance}"
            seed = int.from_bytes(hashlib.sha256(case_id.encode("ascii")).digest()[:8], "little")
            rows.append(record(case_id, random_value(bits, seed), random_value(bits, seed ^ MASK),
                               "splitmix64-v1", f"bits={bits},instance={instance}", seed))
        rows.extend([
            record(f"v2/ones/{bits}", mask, mask, "ones", f"bits={bits}", square="equal-values-distinct-buffers"),
            record(f"v2/near-power/{bits}", top, top + 1, "near-power", f"bits={bits}"),
            record(f"v2/alternating/{bits}", (mask // 3) | top, mask, "alternating", f"bits={bits}"),
            record(f"v2/sparse/{bits}", top | 1 | (1 << (bits // 2)), mask, "sparse", f"bits={bits}"),
        ])
        for ratio in (2, 16, 256):
            right_bits = max(1, bits // ratio)
            a, b = mask, (1 << right_bits) - 1
            for swap in (False, True):
                rows.append(record(f"v2/imbalance/{bits}/{ratio}/{int(swap)}", b if swap else a,
                                   a if swap else b, "imbalance", f"left_width={bits},ratio={ratio},swap={int(swap)}"))
        rows.append(record(f"v2/single-limb/{bits}", mask, 0xffffffff, "single-limb", f"bits={bits}"))
    return list(reversed(rows)) if reverse else rows


def encode(rows):
    lines = [VERSION, "\t".join(FIELDS)]
    count = 0
    for row in rows:
        lines.append("\t".join(row[key] for key in FIELDS))
        count += 1
    body = ("\n".join(lines) + "\n").encode("ascii")
    return body + f"# end\t{count}\t{hashlib.sha256(body).hexdigest()}\n".encode("ascii")


def value(row, side):
    return int(row[f"{side}_sign"]) * int.from_bytes(bytes.fromhex(row[f"{side}_bytes"]), "little")


def validate(stream):
    digest = hashlib.sha256()
    for expected in (VERSION + "\n", "\t".join(FIELDS) + "\n"):
        line = stream.readline()
        require(line == expected.encode("ascii"), "schema/version mismatch")
        digest.update(line)
    seen, rows = set(), []
    while True:
        line = stream.readline()
        require(line and line.endswith(b"\n"), "truncated corpus stream")
        if line.startswith(b"# end\t"):
            tokens = line.decode("ascii").strip().split("\t")
            require(len(tokens) == 3 and tokens[1] == str(len(rows)), "stream count mismatch")
            require(tokens[2] == digest.hexdigest(), "stream manifest hash mismatch")
            require(stream.read(1) == b"", "extra data after trailer")
            return rows
        digest.update(line)
        tokens = line.decode("ascii").rstrip("\n").split("\t")
        require(len(tokens) == len(FIELDS), "record field count")
        row = dict(zip(FIELDS, tokens))
        require(row["id"] and row["id"] not in seen, "duplicate/empty case ID")
        seen.add(row["id"])
        require(hashlib.sha256("\t".join(tokens[:-1]).encode("ascii")).hexdigest() == row["case_sha256"], "case hash mismatch")
        require(row["semantics"] in ("signed-wrapper", "unsigned-kernel"), "invalid semantics")
        require(row["square"] in ("general", "equal-values-distinct-buffers"), "invalid square mode")
        for side in ("left", "right"):
            wire = row[f"{side}_bytes"]
            require(re.fullmatch(r"(?:[0-9a-f]{8})+", wire) is not None, "noncanonical limb bytes")
            require(int(row[f"{side}_limbs"]) == len(wire) // 8, "stored limb length mismatch")
            magnitude = int.from_bytes(bytes.fromhex(wire), "little")
            require(int(row[f"{side}_bits"]) == magnitude.bit_length(), "semantic bit length mismatch")
            sign = int(row[f"{side}_sign"])
            require(sign in (-1, 0, 1) and (sign == 0) == (magnitude == 0), "invalid zero/sign")
            require(row["semantics"] != "unsigned-kernel" or sign >= 0, "signed kernel operand")
        if row["square"] != "general":
            require(value(row, "left") == value(row, "right"), "square values differ")
        rows.append(row)


def validate_legacy(path=ROOT / "mul-v1.tsv"):
    require(hashlib.sha256(path.read_bytes()).hexdigest() == PIN, "legacy corpus changed")
    count = 0
    with path.open(encoding="ascii") as source:
        require(source.readline().startswith("# mul-corpus-v1\t"), "legacy schema mismatch")
        seen = set()
        for line in source:
            fields = line.rstrip("\n").split("\t")
            if line.startswith("#"):
                continue
            require(len(fields) == 7 and fields[0] == "mul", "legacy field mismatch")
            require(fields[1] not in seen, "duplicate legacy ID")
            seen.add(fields[1])
            require(int(fields[4]) * int(fields[5]) == int(fields[6]), "legacy product mismatch")
            count += 1
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--budget", choices=BUDGETS, default="smoke")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_bytes(encode(generate(args.budget)))
