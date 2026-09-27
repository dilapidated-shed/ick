#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
reference=${1:-"$repository_root/gcc"}
output=${2:-"$repository_root/build/ick-source"}

# This file is deliberately shell-readable: the build has one immutable GCC
# reference and immutable source/pruning receipts.
. "$script_dir/SOURCE.lock"

test -d "$reference"

actual_reference=$(git -C "$reference" rev-parse HEAD)
if test "$actual_reference" != "$gcc_commit"; then
  echo "wrong GCC reference: expected $gcc_commit, got $actual_reference" >&2
  exit 1
fi
git -C "$reference" cat-file -e "$gcc_commit:COPYING3"
git -C "$reference" cat-file -e "$gcc_commit:COPYING.RUNTIME"

manifest_paths=$(mktemp "${TMPDIR:-/tmp}/ick-overlay-manifest.XXXXXX")
source_paths=$(mktemp "${TMPDIR:-/tmp}/ick-overlay-source.XXXXXX")
trap 'rm -f "$manifest_paths" "$source_paths"' EXIT HUP INT TERM

awk '{ print $2 }' "$script_dir/OVERLAY.sha256" | LC_ALL=C sort \
  > "$manifest_paths"
(cd "$repository_root" && find ick/source -type f -print | LC_ALL=C sort) \
  > "$source_paths"

# Ordinary ICK-owned modifications are checksummed in OVERLAY.sha256. Imported
# D files that are still byte-for-byte identical to the pinned GCC commit are
# instead verified directly against that commit. Any modified D file must move
# into OVERLAY.sha256, so provenance stays exact without duplicating hundreds
# of checksums for unchanged upstream source.
. "$script_dir/D_SOURCE.lock"

while IFS= read -r source; do
  if grep -Fqx "$source" "$manifest_paths"; then
    continue
  fi

  relative=${source#ick/source/}
  case "$relative" in
    gcc/d/*)
      reference_path=$relative
      ;;
    gcc/config/*-d.cc)
      reference_path=$relative
      case ",$target_hooks," in
        *",${relative#gcc/config/},"*) ;;
        *)
          echo "unmanifested D target hook is not in D_SOURCE.lock: $source" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "unmanifested owned source: $source" >&2
      exit 1
      ;;
  esac

  if ! git -C "$reference" cat-file -e "$gcc_commit:$reference_path" 2>/dev/null; then
    echo "imported D source is absent from pinned GCC: $source" >&2
    exit 1
  fi

  local_blob=$(git hash-object "$repository_root/$source")
  upstream_blob=$(git -C "$reference" rev-parse "$gcc_commit:$reference_path")
  if test "$local_blob" != "$upstream_blob"; then
    echo "modified D source must be recorded in OVERLAY.sha256: $source" >&2
    exit 1
  fi
done < "$source_paths"

while IFS= read -r source; do
  test -f "$repository_root/$source" || {
    echo "overlay manifest names missing source: $source" >&2
    exit 1
  }
done < "$manifest_paths"

(cd "$repository_root" && sha256sum -c ick/OVERLAY.sha256)
rm -f "$manifest_paths" "$source_paths"
trap - EXIT HUP INT TERM

while IFS= read -r path; do
  case "$path" in
    ""|\#*) continue ;;
    /*|*..*)
      echo "unsafe prune path: $path" >&2
      exit 1
      ;;
  esac
  git -C "$reference" cat-file -e "$gcc_commit:$path"
done < "$script_dir/PRUNE"

if test -e "$output"; then
  echo "refusing to overwrite materialized source: $output" >&2
  exit 1
fi

mkdir -p "$output"
git -C "$reference" archive "$gcc_commit" | tar -xf - -C "$output"

while IFS= read -r path; do
  case "$path" in
    ""|\#*) continue ;;
  esac
  rm -rf -- "$output/$path"
  test ! -e "$output/$path"
done < "$script_dir/PRUNE"

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
  C-only prune:  $prune_repository $prune_commit
  output:        $output
EOF
