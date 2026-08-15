#!/usr/bin/env sh
set -eu

directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$directory/MODEL.lock"
base=https://huggingface.co/$MODEL/resolve/$REVISION

fetch() {
    file=$1
    digest=$2
    temporary=$(mktemp "$directory/$file.XXXXXX")
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    curl --fail --location --silent --show-error --output "$temporary" "$base/$file"
    printf '%s  %s\n' "$digest" "$temporary" | sha256sum --check --status
    mv "$temporary" "$directory/$file"
    trap - EXIT HUP INT TERM
}

fetch config.json "$CONFIG_SHA256"
fetch model.safetensors "$MODEL_SHA256"
fetch tokenizer.json "$TOKENIZER_SHA256"
