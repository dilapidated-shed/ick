#!/usr/bin/env python3
"""A measurable FFT-style network shape, NOT an OpenAI-2026 implementation.

Topology-only descriptors for radix-two iterative butterflies and a separate
bit-reversal permutation. These are invariant under changes in machine clock;
their cache-line proxy depends on the chosen model, not observed cache misses.
"""
import argparse
import json
from collections import Counter


def bit_reverse(index, width):
    result = 0
    for _ in range(width):
        result = (result << 1) | (index & 1)
        index >>= 1
    return result


def permutation_cycles(n):
    width = n.bit_length() - 1
    seen = bytearray(n)
    lengths = Counter()
    for i in range(n):
        if seen[i]:
            continue
        j = i
        count = 0
        while not seen[j]:
            seen[j] = 1
            j = bit_reverse(j, width)
            count += 1
        lengths[count] += 1
    return {str(k): lengths[k] for k in sorted(lengths)}


def network_shape(n, cache_line_words=16):
    if n < 2 or n & (n - 1):
        raise ValueError("n must be a power of two, at least 2")
    if cache_line_words < 1:
        raise ValueError("cache_line_words must be positive")
    layers = []
    for exponent in range(n.bit_length() - 1):
        stride = 1 << exponent
        crossed = 0
        total_span = 0
        count = 0
        for first in range(0, n, 2 * stride):
            for offset in range(stride):
                a = first + offset
                b = a + stride
                count += 1
                total_span += b - a
                crossed += a // cache_line_words != b // cache_line_words
        assert count == n // 2
        layers.append({"butterflies": count, "stride_words": stride,
                       "sum_edge_span_words": total_span,
                       "cache_line_crossing_pairs_model": crossed})
    return {"network": "radix2-iterative-FFT-topology", "n_words": n,
            "assumed_line_words": cache_line_words,
            "bit_reverse_permutation_cycle_histogram": permutation_cycles(n),
            "layers": layers,
            "total_butterflies": sum(layer["butterflies"] for layer in layers),
            "total_edge_span_words": sum(layer["sum_edge_span_words"] for layer in layers)}


def operand_shape(x, word_bits=32):
    if x < 0 or word_bits <= 0:
        raise ValueError("expected unsigned integer and positive word_bits")
    count = max(1, (x.bit_length() + word_bits - 1) // word_bits)
    mask = (1 << word_bits) - 1
    words = [(x >> (i * word_bits)) & mask for i in range(count)]
    nonzero = sum(v != 0 for v in words)
    full = sum(v == mask for v in words)
    return {"bit_length": x.bit_length(), "word_bits": word_bits,
            "limbs": count, "hamming_weight": x.bit_count(),
            "nonzero_limbs": nonzero, "full_limbs": full,
            "nonzero_limb_fraction": nonzero / count}


def operand_pair_shape(a, b, word_bits=32):
    left = operand_shape(a, word_bits)
    right = operand_shape(b, word_bits)
    return {"left": left, "right": right,
            "schoolbook_limb_pair_count": left["limbs"] * right["limbs"],
            "nonzero_limb_pair_count": left["nonzero_limbs"] * right["nonzero_limbs"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--butterflies", type=int, metavar="N")
    group.add_argument("--multiply-hex", nargs=2, metavar=("A", "B"))
    parser.add_argument("--word-bits", type=int, default=32)
    parser.add_argument("--cache-line-words", type=int, default=16)
    arguments = parser.parse_args()
    result = (network_shape(arguments.butterflies, arguments.cache_line_words)
              if arguments.butterflies else
              operand_pair_shape(*(int(s, 16) for s in arguments.multiply_hex),
                                 arguments.word_bits))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
