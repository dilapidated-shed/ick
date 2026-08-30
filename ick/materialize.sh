#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
reference=${1:-"$repository_root/gcc"}
output=${2:-"$repository_root/build/ick-source"}

# This file is deliberately shell-readable: the build has one immutable GCC
# reference and one immutable import receipt.
. "$script_dir/SOURCE.lock"

test -d "$reference"

actual_reference=$(git -C "$reference" rev-parse HEAD)
if test "$actual_reference" != "$gcc_commit"; then
  echo "wrong GCC reference: expected $gcc_commit, got $actual_reference" >&2
  exit 1
fi
git -C "$reference" cat-file -e "$gcc_commit:COPYING3"
git -C "$reference" cat-file -e "$gcc_commit:COPYING.RUNTIME"

(cd "$repository_root" && sha256sum -c ick/OVERLAY.sha256)

if test -e "$output"; then
  echo "refusing to overwrite materialized source: $output" >&2
  exit 1
fi

mkdir -p "$output"
git -C "$reference" archive "$gcc_commit" | tar -xf - -C "$output"

find "$script_dir/source" -type f -print | LC_ALL=C sort |
while IFS= read -r source; do
  relative=${source#"$script_dir/source/"}
  destination="$output/$relative"
  mkdir -p "$(dirname -- "$destination")"
  cp -p "$source" "$destination"
done

while read -r checksum source; do
  test -n "$checksum" || continue
  relative=${source#ick/source/}
  printf '%s  %s\n' "$checksum" "$output/$relative"
done < "$script_dir/OVERLAY.sha256" | sha256sum -c -

cat <<EOF
ICK source materialized
  GCC reference: $gcc_repository $gcc_commit
  ICK import:    $import_repository $import_commit
  output:        $output
EOF
