#!/usr/bin/env bash
# Runs only after the unmodified pinned IDK qualification and controls succeed.
set -euo pipefail

source_head=45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0
dmd_lock=74917954b53f7f35b13e61b4438c7253834929ed
phobos_lock=7b158eba80b97dfcdd8931bcaea1ad0ca35ceb95
name=idk-linux-x86_64
out="$GITHUB_WORKSPACE/.runtime-evidence/candidate"
root="$out/$name"
archive="$out/$name-$source_head.tar.gz"
verify="$GITHUB_WORKSPACE/.candidate-ci/dmd/qualification/idk-runtime/verify-candidate.py"

test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
test "$(git rev-parse HEAD)" = "$source_head"
test "$(git -C .runtime-dmd rev-parse HEAD)" = "$dmd_lock"
test "$(git -C .runtime-phobos rev-parse HEAD)" = "$phobos_lock"
test "$PACKAGE_WORKFLOW_HEAD" = "$(git -C .candidate-ci rev-parse HEAD)"
sha256sum -c .runtime-evidence/inputs.sha256
test "$(cat .runtime-evidence/unicode-mutant.exit)" = 3
test "$(cat .runtime-evidence/conservative-idk.exit)" -gt 0
grep -F 'Error: character 0x2192 is not a valid token' \
  .runtime-evidence/conservative-idk.log >/dev/null

compiler=dmd/generated/linux/release/64/dmd
druntime=.runtime-dmd/generated/linux/release/64/libdruntime.a
phobos=.runtime-phobos/generated/linux/release/64/libphobos2.a
test -x "$compiler"
test -s "$druntime"
test -s "$phobos"
test -f .runtime-dmd/druntime/import/object.d
test -f .runtime-phobos/std/bigint.d

mkdir -p "$root/bin" "$root/libexec" "$root/lib" \
  "$root/import/druntime" "$root/import/phobos" \
  "$root/fixtures" "$root/meta" "$root/share" "$root/licenses"
install -m 0755 "$compiler" "$root/libexec/idk-dmd"
install -m 0644 "$druntime" "$root/lib/libdruntime.a"
install -m 0644 "$phobos" "$root/lib/libphobos2.a"
cp -a .runtime-dmd/druntime/import/. "$root/import/druntime/"
cp -a .runtime-phobos/std .runtime-phobos/etc .runtime-phobos/phobos "$root/import/phobos/"
install -m 0644 dmd/SOURCE.lock "$root/meta/SOURCE.lock"
install -m 0644 dmd/RUNTIME.lock "$root/meta/RUNTIME.lock"
install -m 0644 dmd/qualification/idk_ordinary_runtime_smoke.d "$root/fixtures/"
install -m 0644 dmd/qualification/idk_full_runtime_smoke.d "$root/fixtures/"
install -m 0644 "$verify" "$root/share/verify-candidate.py"
install -m 0644 dmd/LICENSE.txt "$root/licenses/IDK-compiler-LICENSE.txt"
install -m 0644 .runtime-phobos/LICENSE_1_0.txt "$root/licenses/Phobos-LICENSE_1_0.txt"

# This wrapper deliberately invokes the owned executable by an absolute,
# bundle-relative path. ldmd2 and conservative-dmd are never runtime fallbacks.
cat > "$root/bin/idk" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
if test "$#" -eq 1 && { test "$1" = "--version" || test "$1" = "-version"; }; then
  exec "$root/libexec/idk-dmd" -conf= "$1"
fi
exec "$root/libexec/idk-dmd" -conf= -fPIC \
  -I"$root/import/druntime" -I"$root/import/phobos" \
  "$@" "$root/lib/libphobos2.a" "$root/lib/libdruntime.a" \
  -defaultlib= -debuglib= -L-lpthread -L-lm -L-ldl
WRAPPER
chmod 0755 "$root/bin/idk"

# Recorded identities are constants, not dynamically guessed runtime sources.
{
  printf 'format=%s\n' 'idk-linux-x86_64-candidate-v1'
  printf 'compiler_line=idk\n'
  printf 'host=linux-x86_64\n'
  printf 'compiler_source_head=%s\n' "$source_head"
  printf 'workflow_source_head=%s\n' "$PACKAGE_WORKFLOW_HEAD"
  printf 'dmd_upstream_commit=%s\n' "$dmd_lock"
  printf 'phobos_upstream_commit=%s\n' "$phobos_lock"
  printf 'source_lock_sha256=%s\n' "$(sha256sum dmd/SOURCE.lock | cut -d' ' -f1)"
  printf 'runtime_lock_sha256=%s\n' "$(sha256sum dmd/RUNTIME.lock | cut -d' ' -f1)"
  printf 'bootstrap_is_payload=false\n'
  printf 'conservative_dmd_is_payload=false\n'
  printf 'linker_deps=pthread,m,dl\n'
  printf 'ordinary_stdout=123456789012345678901234567891\n'
  printf 'divergent_stdout=1000000000000000000000000000000\n'
  printf 'unicode_mutant_exit=3\n'
  printf 'historical_qualification_run=37304142154\n'
  printf 'historical_comparison=source-locks-and-fixture-hashes;not-binary-equality\n'
} > "$root/meta/identity.tsv"

# Reproducible ordering and metadata; build-generated object bytes are recorded
# rather than assumed bit-identical to a different hosted build.
(
  cd "$root"
  LC_ALL=C find . -type f ! -path './meta/FILES.sha256' -print0 \
    | LC_ALL=C sort -z | xargs -0 sha256sum
) > "$root/meta/FILES.sha256"

python3 "$verify" "$root"
(
  cd "$out"
  tar --sort=name --format=gnu --mtime='@0' --owner=0 --group=0 \
    --numeric-owner -cf - "$name" | gzip -n > "$archive"
)
(
  cd "$out"
  sha256sum "$(basename "$archive")" > candidate-archive.sha256
)
sha256sum -c "$out/candidate-archive.sha256" --ignore-missing

# Distinct producer receipt. The fresh-host receipt is created in a separate job.
{
  printf 'receipt_kind\tproducer\n'
  printf 'status\tPASS\n'
  printf 'compiler_source_head\t%s\n' "$source_head"
  printf 'workflow_source_head\t%s\n' "$PACKAGE_WORKFLOW_HEAD"
  printf 'druntime_source_head\t%s\n' "$dmd_lock"
  printf 'phobos_source_head\t%s\n' "$phobos_lock"
  printf 'original_qualification_run\t37304142154\n'
  printf 'original_fixture_comparison\tPINNED_INPUTS_MATCH\n'
  printf 'binary_reproduction_assumption\tNONE\n'
  printf 'compiler_sha256\t%s\n' "$(sha256sum "$root/libexec/idk-dmd" | cut -d' ' -f1)"
  printf 'druntime_sha256\t%s\n' "$(sha256sum "$root/lib/libdruntime.a" | cut -d' ' -f1)"
  printf 'phobos_sha256\t%s\n' "$(sha256sum "$root/lib/libphobos2.a" | cut -d' ' -f1)"
  printf 'manifest_sha256\t%s\n' "$(sha256sum "$root/meta/FILES.sha256" | cut -d' ' -f1)"
  printf 'archive_sha256\t%s\n' "$(sha256sum "$archive" | cut -d' ' -f1)"
  printf 'manifest_path\tmeta/FILES.sha256\n'
  printf 'archive_name\t%s\n' "$(basename "$archive")"
  printf 'negative_control\trejected-original-IDK-fixture\n'
} > .runtime-evidence/idk-candidate-producer.tsv
cat .runtime-evidence/idk-candidate-producer.tsv >> "$GITHUB_STEP_SUMMARY"
