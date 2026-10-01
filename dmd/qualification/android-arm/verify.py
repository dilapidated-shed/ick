#!/usr/bin/env python3
"""Execute owned-DMD ARM objects against independent binary32/ABI oracles.

Clang assembles only the test harness. D source is compiled only by the
supplied owned DMD. QEMU Linux-user execution is not Android device acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import struct
import subprocess
import sys


def bits(value: float) -> int:
    try:
        return struct.unpack('<I', struct.pack('<f', value))[0]
    except OverflowError:
        return 0xFF800000 if value < 0 else 0x7F800000


def value(word: int) -> float:
    return struct.unpack('<f', struct.pack('<I', word & 0xFFFFFFFF))[0]


def f32(number: float) -> float:
    return value(bits(number))


def divide(a: float, b: float) -> float:
    if math.isnan(a) or math.isnan(b) or (a == 0 and b == 0):
        return math.nan
    if b == 0:
        return math.copysign(math.inf, math.copysign(1, a) * math.copysign(1, b))
    return f32(a / b)


def datasets() -> list[dict]:
    rng = random.Random(713664)
    groups: list[dict] = []

    def group(name, signature, result, cases):
        groups.append(dict(name=name, signature=signature, result=result, cases=cases))

    cases = []
    for _ in range(400):
        a, x, b = [f32(rng.uniform(-30, 30)) for _ in range(3)]
        cases.append(([bits(a), bits(x), bits(b)], [], [(bits(f32(f32(a*x)+b)), True)]))
    group('calibrate', 'fff', 'f', cases)

    edges = [0.0, -0.0, 1.0, -1.0, 20.0, -20.0, math.inf, -math.inf,
             math.nan, value(1), value(0x80000001)]
    cases = []
    for x in edges:
        for low, high in [(-4.0, 4.0), (0.0, 1.0), (-math.inf, math.inf)]:
            answer = low if x < low else high if x > high else x
            cases.append(([bits(x), bits(low), bits(high)], [], [(bits(answer), True)]))
    group('clamp_sample', 'fff', 'f', cases)

    cases = []
    for _ in range(24):
        samples = [f32(rng.uniform(-8, 8)) for _ in range(16)]
        a, b = [f32(rng.uniform(-4, 4)) for _ in range(2)]
        for count in [0, 1, 2, 7, 16]:
            answer = b
            for x in samples[:count]:
                answer = f32(answer + f32(a*x))
            cases.append(([0, count, bits(a), bits(b)], [bits(x) for x in samples],
                          [(bits(answer), True)]))
    group('weighted_sum', 'puff', 'f', cases)

    cases = []
    samples = [-10., -4., -1., -0., 0., .5, 1., 4., 10., math.inf, -math.inf, math.nan]
    for count in [0, 1, 5, len(samples)]:
        expected = [(-2. if x < -2. else 3. if x > 3. else x) if i < count else x
                    for i, x in enumerate(samples)]
        cases.append(([0, count, bits(-2.), bits(3.)], [bits(x) for x in samples],
                      [(bits(x), True) for x in expected]))
    group('clip_buffer', 'puff', 'v', cases)

    cases = []
    for x in edges:
        for y in edges:
            mask = int(x < y) + 2*int(x <= y) + 4*int(x == y) + 8*int(x != y) + 16*int(x > y) + 32*int(x >= y)
            cases.append(([bits(x), bits(y)], [], [(mask, False)]))
    group('comparison_mask', 'ff', 'u', cases)

    cases = []
    for p in [0, 1, 6, 17, 255, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF]:
        answer = 1 if p == 6 else 2 if p == 17 else -7 if p > 0x80000000 else -23
        cases.append(([p, (-23) & 0xFFFFFFFF], [], [(answer & 0xFFFFFFFF, False)]))
    group('select_protocol', 'ui', 'i', cases)

    cases = []
    for n in [-4, 0, 1, 2, 3, 4, 8, 9, 10, 400]:
        answer = sum(i for i in range(1, min(n, 8)+1) if i != 3)
        cases.append(([n & 0xFFFFFFFF], [], [(answer, False)]))
    group('control_flow', 'i', 'i', cases)
    group('truth', 'f', 'u', [([bits(x)], [], [(int(x != 0), False)]) for x in edges])
    group('negate', 'f', 'f', [([bits(x)], [], [(bits(-x), True)]) for x in edges])
    group('divide', 'ff', 'f', [([bits(x), bits(y)], [], [(bits(divide(x, y)), True)])
                               for x in edges for y in edges])
    return groups


def assembly(arch: str, groups: list[dict]) -> tuple[str, list[tuple[int, bool, str]]]:
    arm = arch == 'thumb2'
    lines = ['.syntax unified', '.arch armv7-a', '.fpu vfpv3-d16', '.thumb'] if arm else []
    lines += ['.text', '.global _start'] + (['.thumb_func'] if arm else []) + ['_start:']
    if arm:
        lines += ['mov r11, sp', 'movw r7, #0x1771', 'movw r8, #0x2882',
                  'movw r9, #0x3993', 'movw r10, #0x4aa4',
                  'ldr r6, .Loutput_offset', '.balign 4', '.Loutput_pc:', 'add r6, pc']
        lines += [f'vmov d{i}, r8, r9' for i in range(8, 16)]
    else:
        lines += ['mov x23, sp', 'mov x18, #0x1881', 'mov x24, #0x2442',
                  'mov x25, #0x2552', 'mov x26, #0x2662', 'mov x27, #0x2772',
                  'mov x28, #0x2882', 'mov x29, #0x2992',
                  'adrp x21, output', 'add x21, x21, :lo12:output']
        lines += [f'fmov d{i}, x24' for i in range(8, 16)]
    expected = []
    for number, group in enumerate(groups):
        signature, cases = group['signature'], group['cases']
        buffer_len = len(cases[0][1])
        stride = 4 * (len(signature) + buffer_len)
        label = f'.Lloop_{number}'
        if arm:
            lines += [f'ldr r4, .Ltable_offset_{number}', '.balign 4', f'.Ltable_pc_{number}:',
                      'add r4, pc', f'movw r5, #{len(cases)}', label + ':']
            for i, kind in enumerate(signature):
                lines += [f'add.w r{i}, r4, #{4*len(signature)}'] if kind == 'p' else [f'ldr r{i}, [r4, #{4*i}]']
            lines += [f'bl {group["name"]}']
            if group['result'] != 'v':
                lines += ['str r0, [r6], #4']
            else:
                for i in range(buffer_len):
                    lines += [f'ldr r0, [r4, #{4*(len(signature)+i)}]', 'str r0, [r6], #4']
            lines += ['cmp sp, r11', 'bne fail', f'add.w r4, r4, #{stride}', 'subs r5, r5, #1', f'bne {label}']
        else:
            lines += [f'adrp x19, table_{number}', f'add x19, x19, :lo12:table_{number}',
                      f'mov x20, #{len(cases)}', label + ':']
            gpr = fpr = 0
            for i, kind in enumerate(signature):
                if kind == 'p':
                    lines += [f'add x{gpr}, x19, #{4*len(signature)}']; gpr += 1
                elif kind == 'f':
                    lines += [f'ldr s{fpr}, [x19, #{4*i}]']; fpr += 1
                else:
                    lines += [f'ldr w{gpr}, [x19, #{4*i}]']; gpr += 1
            lines += [f'bl {group["name"]}']
            if group['result'] != 'v':
                lines += [f'str {"s0" if group["result"] == "f" else "w0"}, [x21], #4']
            else:
                for i in range(buffer_len):
                    lines += [f'ldr w0, [x19, #{4*(len(signature)+i)}]', 'str w0, [x21], #4']
            lines += ['mov x0, sp', 'cmp x0, x23', 'b.ne fail', f'add x19, x19, #{stride}',
                      'subs x20, x20, #1', f'b.ne {label}']
        for row, (_, _, words) in enumerate(cases):
            expected.extend((word, isfloat, f'{group["name"]}[{row}][{i}]') for i, (word, isfloat) in enumerate(words))
    # Verify platform and callee-saved registers as well as stack restoration.
    if arm:
        for register, sentinel in [(7, 0x1771), (8, 0x2882), (9, 0x3993), (10, 0x4AA4)]:
            lines += [f'movw r0, #{sentinel}', f'cmp r{register}, r0', 'bne fail']
        for register in range(8, 16):
            lines += [f'vmov r0, r1, d{register}', 'cmp r0, r8', 'bne fail', 'cmp r1, r9', 'bne fail']
        lines += ['ldr r1, .Lwrite_offset', '.balign 4', '.Lwrite_pc:', 'add r1, pc',
                  'movs r0, #1', f'movw r2, #{4*len(expected)}', 'movs r7, #4', 'svc #0',
                  f'movw r1, #{4*len(expected)}', 'cmp r0, r1', 'bne fail',
                  'movs r0, #0', 'movs r7, #1', 'svc #0',
                  'fail:', 'movs r0, #99', 'movs r7, #1', 'svc #0', '.balign 4',
                  '.Loutput_offset: .word output - (.Loutput_pc + 4)',
                  '.Lwrite_offset: .word output - (.Lwrite_pc + 4)']
        for i in range(len(groups)):
            lines += [f'.Ltable_offset_{i}: .word table_{i} - (.Ltable_pc_{i} + 4)']
    else:
        for register, sentinel in [(18,0x1881),(24,0x2442),(25,0x2552),(26,0x2662),(27,0x2772),(28,0x2882),(29,0x2992)]:
            lines += [f'mov x0, #{sentinel}', f'cmp x{register}, x0', 'b.ne fail']
        for register in range(8, 16):
            lines += [f'fmov x0, d{register}', 'cmp x0, x24', 'b.ne fail']
        lines += ['adrp x1, output', 'add x1, x1, :lo12:output', 'mov x0, #1',
                  f'mov x2, #{4*len(expected)}', 'mov x8, #64', 'svc #0',
                  f'mov x1, #{4*len(expected)}', 'cmp x0, x1', 'b.ne fail',
                  'mov x0, #0', 'mov x8, #93', 'svc #0',
                  'fail:', 'mov x0, #99', 'mov x8, #93', 'svc #0']
    lines += ['.data', '.balign 16']
    for i, group in enumerate(groups):
        lines += [f'table_{i}:']
        for args, buffer, _ in group['cases']:
            lines += ['.word ' + ', '.join(f'0x{x:08x}' for x in args+buffer)]
    lines += ['.bss', '.balign 16', 'output:', f'.space {4*len(expected)}',
              '.section .note.GNU-stack,"",%progbits']
    return '\n'.join(lines)+'\n', expected


def run(command: list[str], *, output: Path | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    if output is not None:
        output.write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f'command failed ({result.returncode}): {command!r}\n{result.stderr.decode(errors="replace")}')
    return result


def check(actual: bytes, expected: list[tuple[int, bool, str]]) -> None:
    if len(actual) != 4*len(expected):
        raise RuntimeError(f'output length {len(actual)} != {4*len(expected)}')
    for (got,), (want, isfloat, label) in zip(struct.iter_unpack('<I', actual), expected):
        if got == want or (isfloat and math.isnan(value(got)) and math.isnan(value(want))):
            continue
        raise RuntimeError(f'{label}: got 0x{got:08x} ({value(got)}), wanted 0x{want:08x} ({value(want)})')


def check_object(path: Path, arch: str) -> None:
    data = path.read_bytes()
    elf_class, machine = (1, 40) if arch == 'thumb2' else (2, 183)
    if (len(data) < 52 or data[:4] != b'\x7fELF' or
        data[4:8] != bytes([elf_class, 1, 1, 0]) or
        struct.unpack_from('<HH', data, 16) != (1, machine)):
        raise RuntimeError(f'{path}: incorrect ELF class, endianness, OSABI, type or machine')
    if arch == 'thumb2':
        flags = struct.unpack_from('<I', data, 36)[0]
        if flags != 0x05000000:
            raise RuntimeError(f'{path}: expected EABI5, not hard-float ABI flags')


def negative_tests(compiler: str, imports: str, out: Path) -> int:
    bad_sources = {
        'double': 'extern(C) double bad(double x) { return x; }',
        'real': 'extern(C) real bad(real x) { return x; }',
        'call': 'extern(C) float helper(float); extern(C) float bad(float x) { return helper(x); }',
        'indirect_call': 'extern(C) float helper(float); extern(C) float bad(float x) { auto f = &helper; return f(x); }',
        'five_arguments': 'extern(C) float bad(float a,float b,float c,float d,float e) { return e; }',
        'global': 'int state; extern(C) int bad() { return state; }',
        'aggregate': 'struct Pair { float a,b; } extern(C) Pair bad(Pair x) { return x; }',
        'reference': 'extern(C) float bad(ref float x) { return x; }',
        'integer_division': 'extern(C) int bad(int x,int y) { return x/y; }',
        'float_conversion': 'extern(C) int bad(float x) { return cast(int)x; }',
        'void_initialization': 'extern(C) float bad() { float x=void; return x; }',
        'frame_bound': 'extern(C) int bad(int x) {' + ''.join(f'int a{i}=x+{i};' for i in range(128)) + 'return a127;}',
    }
    count = 0
    for name in ['double', 'real', 'indirect_call', 'five_arguments', 'global', 'aggregate',
                 'reference', 'integer_division', 'float_conversion',
                 'void_initialization', 'frame_bound']:
        source = bad_sources[name]
        file = out / f'reject_{name}.d'; file.write_text(source)
        obj = out / f'reject_{name}.o'; obj.write_bytes(b'stale output must be removed')
        command = [compiler, '-target=armv7a-linux-androideabi21', '-betterC', '-c', f'-I{imports}', str(file), f'-of={obj}']
        result = subprocess.run(command, capture_output=True, timeout=30)
        (out/f'reject_{name}.log').write_bytes(result.stdout+result.stderr)
        if result.returncode == 0 or obj.exists() or b'Thumb-2 backend:' not in result.stderr:
            raise RuntimeError(f'fail-closed rejection failed for {name}: {result.stderr.decode(errors="replace")}')
        count += 1
    # The existing AArch64 generator must not advertise unqualified runtime,
    # aggregate or extended-real support merely because it emits ELF.
    for name in ['double', 'real', 'indirect_call', 'five_arguments', 'global', 'aggregate',
                 'reference', 'void_initialization']:
        file = out / f'aarch64_reject_{name}.d'; file.write_text(bad_sources[name])
        obj = out / f'aarch64_reject_{name}.o'; obj.write_bytes(b'stale output must be removed')
        command = [compiler, '-target=aarch64-linux-android21', '-betterC', '-c', f'-I{imports}', str(file), f'-of={obj}']
        result = subprocess.run(command, capture_output=True, timeout=30)
        (out/f'aarch64_reject_{name}.log').write_bytes(result.stdout+result.stderr)
        marker = b'AArch64 Android leaf boundary:' in result.stderr
        if result.returncode == 0 or obj.exists() or not marker:
            raise RuntimeError(
                f'AArch64 rejection failed for {name}: '
                f'returncode={result.returncode} object_exists={obj.exists()} marker={marker}\n'
                f'{result.stderr.decode(errors="replace")}'
            )
        count += 1
    good = out/'target_probe.d'; good.write_text('extern(C) int probe(int x) {return x;}')
    for target in ['armv7a-linux-android21', 'aarch64-linux-androideabi21', 'armv7a-linux-androideabi20',
                   'armv7a-windows-androideabi21', 'armv7a-linux-gnu', 'armv7a-linux-androideabi21-junk']:
        result = subprocess.run([compiler, f'-target={target}', '-betterC', '-c', f'-I{imports}', str(good), f'-of={out/"bad_target.o"}'], capture_output=True, timeout=30)
        if result.returncode == 0 or b'compiler bug' in result.stderr:
            raise RuntimeError(f'invalid target was not cleanly rejected: {target}')
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--imports', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--linker', default='ld.lld')
    parser.add_argument('--qemu-arm', default=os.environ.get('QEMU_ARM', 'qemu-arm-static'))
    parser.add_argument('--qemu-aarch64', default=os.environ.get('QEMU_AARCH64', 'qemu-aarch64-static'))
    args = parser.parse_args()
    out = Path(args.output).resolve(); out.mkdir(parents=True, exist_ok=True)
    (out/'receipt.json').unlink(missing_ok=True)
    compiler = str(Path(args.compiler).resolve())
    imports = str(Path(args.imports).resolve())
    source = Path(__file__).resolve().with_name('leaves.d')
    groups = datasets()
    receipt = {'boundary': 'Linux-user emulation, NOT Android device/runtime acceptance',
               'compiler_sha256': hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
               'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'targets': []}
    for arch, target, machine, qemu in [
        ('thumb2', 'armv7a-linux-androideabi21', 'armelf_linux_eabi', args.qemu_arm),
        ('aarch64', 'aarch64-linux-android21', 'aarch64linux', args.qemu_aarch64),
    ]:
        harness, expected = assembly(arch, groups)
        asm = out/f'{arch}.s'; asm.write_text(harness)
        harness_object = out/f'{arch}_harness.o'
        run([args.clang, f'--target={target}', '-c', str(asm), '-o', str(harness_object)])
        for optimized in [False, True]:
            name = arch + ('-optimized' if optimized else '-unoptimized')
            obj = out/f'{name}.o'; executable = out/name
            command = [compiler, f'-target={target}', '-betterC', '-c', f'-I{imports}', str(source), f'-of={obj}']
            if optimized: command += ['-O']
            run(command)
            check_object(obj, arch)
            run([args.linker, '-m', machine, '-static', '-e', '_start', str(harness_object), str(obj), '-o', str(executable)])
            result = run([qemu, str(executable)], output=out/f'{name}.bin')
            check(result.stdout, expected)
            receipt['targets'].append({'architecture': arch, 'optimized': optimized,
                                       'cases': sum(len(g['cases']) for g in groups), 'checked_words': len(expected),
                                       'status': 'PASS', 'compile_command': command})
            print(f'PASS {name}: {sum(len(g["cases"]) for g in groups)} cases, {len(expected)} checked words; registers and stack preserved', flush=True)
    receipt['negative_cases'] = negative_tests(compiler, imports, out)
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(f'PASS {receipt["negative_cases"]} negative cases; receipt: {out/"receipt.json"}', flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
