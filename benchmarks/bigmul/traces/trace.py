#!/usr/bin/env python3
"""Trace-v1 validator; model fixtures must not claim executed provenance."""
import csv
import hashlib
import io

FIELDS = "seq kind buffer index value dependencies word_bits units".split()
KINDS = {"allocate", "read", "write", "multiply-accumulate", "carry", "result", "free", "end"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def case_hash(a, b):
    payload = b"".join(value.to_bytes(4, "little") for value in a) + b"|" + b"".join(value.to_bytes(4, "little") for value in b)
    return hashlib.sha256(payload).hexdigest()


def validate(text, source_sha, binary_sha, a, b):
    stream = io.StringIO(text)
    require(stream.readline() == "trace-v1\n", "unsupported trace version")
    metadata = {}
    for key in ("source_sha256", "binary_sha256", "case_sha256", "profile", "complete", "coordinate_space"):
        tokens = stream.readline().rstrip("\n").split("\t")
        require(len(tokens) == 2 and tokens[0] == key, "trace metadata schema")
        metadata[key] = tokens[1]
    require(metadata["source_sha256"] == source_sha and metadata["binary_sha256"] == binary_sha, "wrong executable/source trace")
    require(metadata["case_sha256"] == case_hash(a, b), "wrong case trace")
    require(metadata["complete"] == "1", "incomplete trace")
    require(metadata["profile"] == "executed-schoolbook-control", "unsupported execution profile")
    require(metadata["coordinate_space"] == "logical-limb-index", "coordinate-space mismatch")
    reader = csv.DictReader(stream, delimiter="\t")
    require(reader.fieldnames == FIELDS, "event schema mismatch")
    events, active, values, result, counts, last_write = [], {}, {}, {}, {}, {}
    for sequence, raw in enumerate(reader):
        require(None not in raw and all(value is not None for value in raw.values()), "truncated event")
        event = dict(raw)
        for field in ("seq", "index", "value", "word_bits"):
            event[field] = int(raw[field])
        require(event["seq"] == sequence, "dropped/duplicate event sequence")
        kind, buffer, index, value = (event[key] for key in ("kind", "buffer", "index", "value"))
        require(kind in KINDS and index >= 0 and value >= 0, "unsupported event")
        require(event["word_bits"] == (64 if kind == "multiply-accumulate" else 32), "word-width mismatch")
        require(value < 1 << event["word_bits"], "value exceeds width")
        expected_unit = "limbs" if kind in ("allocate", "free") else "operations" if kind == "end" else "value"
        require(event["units"] == expected_unit, "unsupported event units")
        dependencies = [] if raw["dependencies"] == "-" else [int(token) for token in raw["dependencies"].split(",")]
        require(all(0 <= dep < sequence for dep in dependencies) and len(set(dependencies)) == len(dependencies), "bad dependency reference")
        event["dependencies"] = dependencies
        if kind == "allocate":
            require(buffer in ("a", "b", "out") and buffer not in active and value > 0, "bad buffer lifetime")
            active[buffer] = value
        elif kind == "free":
            require(buffer in active, "double/unallocated free")
            del active[buffer]
        elif kind != "end":
            require(buffer in active and index < active[buffer], "reference outside live buffer")
            if kind == "write":
                if dependencies:
                    require(len(dependencies) == 1, "write dependency count")
                    parent = events[dependencies[0]]
                    require(value == parent["value"] & 0xffffffff, "wrong arithmetic store")
                values[buffer, index] = value
                last_write[buffer, index] = sequence
            elif kind in ("read", "result"):
                require(dependencies == [last_write.get((buffer, index))], "missing/stale last-write dependency")
                require(values.get((buffer, index)) == value, "read/result disagrees with stored value")
                if kind == "result":
                    require(index not in result, "duplicate output limb")
                    result[index] = value
            elif kind == "multiply-accumulate":
                require(len(dependencies) in (3, 4), "missing arithmetic operands")
                inputs = [events[dep] for dep in dependencies]
                require([item["kind"] for item in inputs[:3]] == ["read"] * 3 and
                        [item["buffer"] for item in inputs[:3]] == ["a", "b", "out"], "wrong arithmetic inputs")
                carry = inputs[3]["value"] if len(inputs) == 4 else 0
                if len(inputs) == 4:
                    require(inputs[3]["kind"] == "carry", "wrong carry input")
                require(value == inputs[0]["value"] * inputs[1]["value"] + inputs[2]["value"] + carry,
                        "arithmetic trace mismatch")
            elif kind == "carry":
                require(len(dependencies) == 1 and events[dependencies[0]]["kind"] == "multiply-accumulate", "carry origin")
                require(value == events[dependencies[0]]["value"] >> 32, "wrong carry")
        else:
            require(not active and value == len(a) * len(b), "missing lifetime/arithmetic completion")
        counts[kind] = counts.get(kind, 0) + 1
        events.append(event)
    require(events and events[-1]["kind"] == "end" and counts.get("end") == 1, "missing final event")
    require(counts.get("allocate") == counts.get("free") == 3, "lifetime count")
    require(counts.get("multiply-accumulate") == counts.get("carry") == len(a)*len(b), "arithmetic count mismatch")
    require(counts.get("read") == 3*len(a)*len(b), "read count mismatch")
    require(set(result) == set(range(len(a)+len(b))), "missing output words")
    require([values.get(("a", i)) for i in range(len(a))] == a and
            [values.get(("b", i)) for i in range(len(b))] == b, "changed input")
    output = sum(result[index] << (32*index) for index in result)
    expected = sum(value << (32*i) for i, value in enumerate(a)) * sum(value << (32*i) for i, value in enumerate(b))
    require(output == expected, "wrong traced product")
    return {"metadata": metadata, "events": events, "counts": counts, "output": output}
