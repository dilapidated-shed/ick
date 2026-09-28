#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
upstream=https://bitbucket.org/acehreli/ddili.git
mirror="$repo_root/references/d/programming-in-d.git"

mkdir -p "$repo_root/references/d"

if [ -d "$mirror" ]; then
    git -C "$mirror" remote set-url origin "$upstream"
    git -C "$mirror" remote update --prune
else
    git clone --mirror "$upstream" "$mirror"
fi

printf 'Programming in D mirror: %s\n' "$mirror"
git -C "$mirror" show -s --format='upstream HEAD: %H %cI %s' HEAD
