#!/usr/bin/env bash
# Called only on a separate, clean Linux x86_64 runner with no source checkout.
set -euo pipefail
test "$#" -eq 3
bundle="$(realpath "$1")"
evidence="$(realpath -m "$2")"
archive="$3"
mkdir -p "$evidence"
receipt="$evidence/fresh-consumer.tsv"
{
  printf 'receipt_kind\tfresh-linux-x86_64-consumer\n'
  printf 'compiler_source_head\t45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0\n'
  printf 'archive_sha256\t%s\n' "$(sha256sum "$archive" | cut -d' ' -f1)"
  printf 'source_checkout\tNONE\n'
  printf 'DMD_fallback\tFORBIDDEN\n'
  printf 'linker_deps\tpthread,m,dl\n'
} > "$receipt"
trap 'status=$?; printf "overall_exit\t%s\n" "$status" >> "$receipt"' EXIT

test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
# A clean PATH is imposed on the compiler and all executed fixtures. No
# installed DMD, LDC or ldmd2 may silently satisfy a compiler invocation.
for fallback in dmd ldmd2 ldc2; do
  if PATH=/usr/bin:/bin command -v "$fallback" >/dev/null 2>&1; then
    echo "BLOCKED: system D compiler is present in clean consumer PATH: $fallback" >&2
    exit 1
  fi
done
printf 'system_D_compiler\tABSENT\n' >> "$receipt"

python3 "$bundle/share/verify-candidate.py" "$bundle" \
  > "$evidence/initial-integrity.stdout"
printf 'initial_integrity_and_abi\tPASS\n' >> "$receipt"

env -i PATH=/usr/bin:/bin HOME="$evidence" \
  "$bundle/bin/idk" "$bundle/fixtures/idk_ordinary_runtime_smoke.d" \
  -of="$evidence/ordinary-d"
"$evidence/ordinary-d" > "$evidence/ordinary.stdout"
test "$(cat "$evidence/ordinary.stdout")" = '123456789012345678901234567891'
printf 'ordinary_compile_execute\tPASS\n' >> "$receipt"
printf 'ordinary_stdout\t%s\n' "$(cat "$evidence/ordinary.stdout")" >> "$receipt"

env -i PATH=/usr/bin:/bin HOME="$evidence" \
  "$bundle/bin/idk" "$bundle/fixtures/idk_full_runtime_smoke.d" \
  -of="$evidence/divergent-idk"
"$evidence/divergent-idk" > "$evidence/divergent.stdout"
test "$(cat "$evidence/divergent.stdout")" = '1000000000000000000000000000000'
printf 'divergent_compile_execute\tPASS\n' >> "$receipt"
printf 'divergent_stdout\t%s\n' "$(cat "$evidence/divergent.stdout")" >> "$receipt"

fixture="$bundle/fixtures/idk_full_runtime_smoke.d"
test "$(grep -Fc '3 × 4 ≟ 12' "$fixture")" -eq 1
sed 's/3 × 4 ≟ 12/3 − 4 ≟ 12/' "$fixture" \
  > "$evidence/idk_unicode_mutant.d"
test "$(grep -Fc '3 − 4 ≟ 12' "$evidence/idk_unicode_mutant.d")" -eq 1
env -i PATH=/usr/bin:/bin HOME="$evidence" \
  "$bundle/bin/idk" "$evidence/idk_unicode_mutant.d" \
  -of="$evidence/unicode-mutant"
status=0
"$evidence/unicode-mutant" > "$evidence/mutant.stdout" || status=$?
printf '%s\n' "$status" > "$evidence/mutant.exit"
test "$status" -eq 3
test "$(cat "$evidence/mutant.stdout")" = '1000000000000000000000000000000'
printf 'unicode_mutant_compile_execute\tPASS\n' >> "$receipt"
printf 'unicode_mutant_actual_exit\t%s\n' "$status" >> "$receipt"

# Negative controls are applied to this unpacked copy only and restored after
# each test. The verifier must return code 1, with the expected rejection.
reject() {
  local label="$1" diagnostic="$2" status=0
  python3 "$bundle/share/verify-candidate.py" "$bundle" \
    > "$evidence/$label.stdout" 2> "$evidence/$label.stderr" || status=$?
  test "$status" -eq 1
  grep -F "$diagnostic" "$evidence/$label.stderr" >/dev/null
  printf '%s\tPASS\n' "$label" >> "$receipt"
}

for lib in libdruntime.a libphobos2.a; do
  item="$bundle/lib/$lib"
  cp "$item" "$evidence/$lib.original"
  rm "$item"
  reject "reject-missing-$lib" "missing required bundle member"
  cp "$evidence/$lib.original" "$item"
done

cp "$bundle/meta/identity.tsv" "$evidence/identity.original"
sed -i 's/^compiler_source_head=.*/compiler_source_head=0000000000000000000000000000000000000000/' \
  "$bundle/meta/identity.tsv"
reject reject-mismatched-IDK-source 'mismatched source/runtime identity'
cp "$evidence/identity.original" "$bundle/meta/identity.tsv"

cp "$bundle/meta/RUNTIME.lock" "$evidence/runtime-lock.original"
sed -i 's/^phobos_upstream_commit=.*/phobos_upstream_commit=0000000000000000000000000000000000000000/' \
  "$bundle/meta/RUNTIME.lock"
reject reject-mismatched-runtime 'mismatched runtime identity'
cp "$evidence/runtime-lock.original" "$bundle/meta/RUNTIME.lock"

for lib in libdruntime.a libphobos2.a; do
  item="$bundle/lib/$lib"
  python3 - "$item" <<'PY'
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
data = bytearray(p.read_bytes())
start = data.find(b"\x7fELF")
if start < 0 or start + 20 > len(data):
    raise SystemExit("no archive ELF object to mutate")
data[start + 18:start + 20] = (183).to_bytes(2, "little")  # AArch64, wrong ABI
p.write_bytes(data)
PY
  reject "reject-wrong-ABI-$lib" 'wrong-ABI ELF'
  cp "$evidence/$lib.original" "$item"
done

cp "$bundle/import/phobos/std/stdio.d" "$evidence/stdio.original"
printf '\n// tampered by fresh-consumer negative test\n' \
  >> "$bundle/import/phobos/std/stdio.d"
reject reject-tampered-import 'tampered package member'
cp "$evidence/stdio.original" "$bundle/import/phobos/std/stdio.d"

python3 "$bundle/share/verify-candidate.py" "$bundle" \
  > "$evidence/restored-integrity.stdout"
printf 'restored_integrity\tPASS\n' >> "$receipt"
printf 'overall_status\tPASS\n' >> "$receipt"
