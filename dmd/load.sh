#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dest="$repo_root/dmd"
lock="$dest/SOURCE.lock"

upstream_repository=https://github.com/dlang/dmd.git
upstream_tag=v2.113.0
upstream_commit=74917954b53f7f35b13e61b4438c7253834929ed
upstream_compiler_src_dmd_tree=609b890e7cfc65474e5fdebd001c580e174cd22b

if [ -e "$lock" ]; then
    echo "DMD source is already loaded; refusing to overwrite $lock" >&2
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
upstream="$tmp/dmd"

git init -q "$upstream"
git -C "$upstream" remote add origin "$upstream_repository"
git -C "$upstream" fetch -q --depth=1 origin "$upstream_commit"
git -C "$upstream" checkout -q --detach FETCH_HEAD

actual_commit=$(git -C "$upstream" rev-parse HEAD)
test "$actual_commit" = "$upstream_commit"

actual_tree=$(git -C "$upstream" rev-parse HEAD:compiler/src/dmd)
test "$actual_tree" = "$upstream_compiler_src_dmd_tree"

mkdir -p "$dest/compiler/src"
cp -a "$upstream/compiler/src/dmd" "$dest/compiler/src/dmd"
for file in README.md bootstrap.sh build.d osmodel.mak; do
    cp -p "$upstream/compiler/src/$file" "$dest/compiler/src/$file"
done
cp -p "$upstream/LICENSE.txt" "$dest/LICENSE.txt"
cp -p "$upstream/VERSION" "$dest/VERSION"

file_count=$(find "$dest/compiler/src/dmd" -type f | wc -l | tr -d ' ')
test "$file_count" = 329

cat > "$lock" <<EOF
# Standalone Digital Mars DMD import provenance
upstream_repository=$upstream_repository
upstream_tag=$upstream_tag
upstream_commit=$upstream_commit
upstream_compiler_src_dmd_tree=$upstream_compiler_src_dmd_tree
destination=dmd/compiler/src/dmd
imported_compiler_files=329
imported_compiler_bytes=12948048
build_metadata=compiler/src/README.md,compiler/src/bootstrap.sh,compiler/src/build.d,compiler/src/osmodel.mak
license_file=LICENSE.txt
version_file=VERSION
runtime=not_imported
runtime_note=druntime_and_phobos_are_outside_this_compiler_snapshot
upstream_tests=not_imported
spec=not_imported
upstream_ci=not_imported
EOF

echo "Loaded DMD $upstream_tag ($upstream_commit): $file_count compiler files"
