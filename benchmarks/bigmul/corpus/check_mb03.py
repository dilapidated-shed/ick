#!/usr/bin/env python3
import hashlib
import io
import json
from pathlib import Path
from corpus import ROOT, encode, generate, require, splitmix, validate, validate_legacy, value


def main():
    require(splitmix(0)[1] == 0xe220a8397b1dcdaf, "SplitMix64 known vector")
    smoke, medium = generate(), generate("medium")
    first = encode(smoke)
    require(first == encode(generate()), "repeatability")
    lookup = {r["id"]: r for r in medium}
    for row in smoke:
        require(row == lookup[row["id"]], "budget changes existing case")
    require({r["id"]: r for r in validate(io.BytesIO(encode(generate(reverse=True))))} ==
            {r["id"]: r for r in smoke}, "enumeration order changes bytes")
    require(validate(io.BytesIO(first)) == smoke, "roundtrip")
    # Wire layout is specified per uint32 word, without native struct packing.
    for row in smoke:
        for side in ("left", "right"):
            data = bytes.fromhex(row[f"{side}_bytes"])
            words = [int.from_bytes(data[k:k+4], "little") for k in range(0, len(data), 4)]
            reconstructed = sum(word << (32*k) for k, word in enumerate(words))
            require(reconstructed == abs(value(row, side)), "word-size-independent roundtrip")
    mutations = {
        "manifest-hash": first[:-2] + b"0\n",
        "operand": first.replace(b"00000000", b"01000000", 1),
        "duplicate-id": encode(smoke + [smoke[0]]),
        "truncated-row": first[:-100],
        "missing-trailer": first[:first.rfind(b"# end")],
    }
    rejected = []
    for name, payload in mutations.items():
        try:
            validate(io.BytesIO(payload))
        except (ValueError, UnicodeError):
            rejected.append(name)
        else:
            raise ValueError(f"corpus defect passed: {name}")
    checked = ROOT / "smoke-v2.tsv"
    require(checked.read_bytes() == first, "committed smoke corpus drift")
    print(json.dumps({"job": "MB03", "status": "PASS", "cases": len(smoke),
                      "legacy_cases": validate_legacy(), "mutants_rejected": rejected,
                      "smoke_sha256": hashlib.sha256(first).hexdigest()}))


if __name__ == "__main__":
    main()
