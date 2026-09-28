#!/usr/bin/env python3
"""Run separately recorded Android-device acceptance, never an emulation receipt.

Requires an explicitly selected adb serial. Uses only /data/local/tmp under a
fresh random directory and deletes that directory afterwards. Does not install
an APK, compiler or library, change settings, or request root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import uuid

from verify import assembly, check, check_object, datasets, run


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--architecture', choices=['thumb2', 'aarch64'], required=True)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--imports', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--linker', default='ld.lld')
    parser.add_argument('--prepare-only', action='store_true', help='build PIE probes without contacting a device; NOT a device PASS')
    args = parser.parse_args()
    arm = args.architecture == 'thumb2'
    target = 'armv7a-linux-androideabi21' if arm else 'aarch64-linux-android21'
    abi = 'armeabi-v7a' if arm else 'arm64-v8a'
    machine = 'armelf_linux_eabi' if arm else 'aarch64linux'
    interpreter = '/system/bin/linker' if arm else '/system/bin/linker64'
    out = Path(args.output).resolve(); out.mkdir(parents=True, exist_ok=True)
    (out/'device-receipt.json').unlink(missing_ok=True)
    compiler = str(Path(args.compiler).resolve())
    imports = str(Path(args.imports).resolve())
    source = Path(__file__).resolve().with_name('leaves.d')
    groups = datasets()
    harness, expected = assembly(args.architecture, groups)
    asm = out/'harness.s'; asm.write_text(harness)
    harness_object = out/'harness.o'
    run([args.clang, f'--target={target}', '-c', str(asm), '-o', str(harness_object)])
    probes = []
    for optimized in [False, True]:
        name = 'optimized' if optimized else 'unoptimized'
        obj = out/f'{name}.o'; binary = out/name
        command = [compiler, f'-target={target}', '-betterC', '-c', f'-I{imports}', str(source), f'-of={obj}']
        if optimized: command += ['-O']
        run(command); check_object(obj, args.architecture)
        run([args.linker, '-m', machine, '-pie', '-e', '_start', '--dynamic-linker', interpreter,
             '-z', 'max-page-size=16384', '-z', 'noexecstack', '-z', 'text',
             str(harness_object), str(obj), '-o', str(binary)])
        probes.append((name, binary))
    receipt_path = out/'device-receipt.json'
    # Never leave a previous PASS while preparing or attempting a new run.
    receipt = {'status': 'PREPARED_NOT_EXECUTED', 'boundary': 'Android device execution',
               'architecture': args.architecture,
               'compiler_sha256': hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
               'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
               'probes': []}
    receipt_path.write_text(json.dumps(receipt, indent=2)+'\n')
    if args.prepare_only:
        print('PREPARED: PIE probes; Android execution NOT performed')
        return 0
    adb = [args.adb, '-s', args.serial]
    actual_abis = run(adb+['shell', 'getprop', 'ro.product.cpu.abilist']).stdout.decode().strip().split(',')
    if abi not in actual_abis:
        raise RuntimeError(f'device ABI list {actual_abis!r} does not include {abi}')
    receipt['sdk'] = run(adb+['shell', 'getprop', 'ro.build.version.sdk']).stdout.decode().strip()
    if int(receipt['sdk']) < 21:
        raise RuntimeError('Android API 21 or newer required')
    remote = '/data/local/tmp/icky-dmd-arm-' + uuid.uuid4().hex
    run(adb+['shell', 'mkdir', remote])
    try:
        for name, binary in probes:
            path = remote + '/' + name
            run(adb+['push', str(binary), path])
            run(adb+['shell', 'chmod', '700', path])
            result = run(adb+['exec-out', path], output=out/f'{name}.bin')
            check(result.stdout, expected)
            receipt['probes'].append({'mode': name, 'status': 'PASS',
                                      'cases': sum(len(g['cases']) for g in groups),
                                      'checked_words': len(expected),
                                      'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()})
        receipt['status'] = 'PASS'
    except (OSError, RuntimeError, subprocess.TimeoutExpired):
        receipt['status'] = 'FAIL'
        raise
    finally:
        # The random, locally generated path cannot select an existing user directory.
        cleanup = subprocess.run(adb+['shell', 'rm', '-r', remote], capture_output=True, timeout=30)
        receipt['cleanup_status'] = cleanup.returncode
        receipt_path.write_text(json.dumps(receipt, indent=2)+'\n')
    print(f'PASS Android {abi}: {len(probes)} modes; receipt: {receipt_path}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
