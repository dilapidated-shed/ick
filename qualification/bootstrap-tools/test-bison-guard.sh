#!/bin/sh
# Lightweight guard checks. This is not a compiler or Flex qualification.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -p "$root/source/gcc/c" "$root/bin"
printf 'gengtype-lex.cc : gengtype-lex.l\n' > "$root/source/gcc/Makefile.in"
printf '%%option noinput\n' > "$root/source/gcc/gengtype-lex.l"
printf 'handwritten parser\n' > "$root/source/gcc/gengtype-parse.cc"
cat > "$root/bin/flex" <<'EOF_FLEX'
#!/bin/sh
printf 'mock flex for guard tests\n'
EOF_FLEX
chmod 0755 "$root/bin/flex"
: > "$root/gh-env"
: > "$root/gh-path"
GITHUB_WORKSPACE=$root GITHUB_ENV=$root/gh-env GITHUB_PATH=$root/gh-path \
  PATH="$root/bin:$PATH" sh "$here/bison-guard.sh" setup "$root/source" >/dev/null
shadow=$root/.ick-bootstrap-guard
export ICK_BISON_LOG=$shadow/bison-invocations.tsv
if "$shadow/bison" --version; then
  echo 'a Bison probe incorrectly passed' >&2
  exit 1
fi
printf 'generated lexer fixture\n' > "$root/gengtype-lex.cc"
printf '0 execve("%s/bison", ["bison", "--version"], ...) = 86\n' \
  "$shadow" > "$shadow/configure.execve"
printf '0 execve("/usr/bin/flex", ["flex", "-ogengtype-lex.cc"], ...) = 0\n' \
  > "$shadow/build.execve"
printf '0 execve("/usr/bin/install", ["install"], ...) = 0\n' \
  > "$shadow/install.execve"
GITHUB_WORKSPACE=$root sh "$here/bison-guard.sh" verify "$root/gengtype-lex.cc" traced >/dev/null

# Negative control 1: real generation must fail, even with a fabricated lexer.
if "$shadow/yacc" -o parse.cc parse.y; then
  echo 'a Yacc generation call incorrectly passed' >&2
  exit 1
fi
if GITHUB_WORKSPACE=$root sh "$here/bison-guard.sh" verify "$root/gengtype-lex.cc" traced >/dev/null 2>&1; then
  echo 'a generator call was incorrectly accepted' >&2
  exit 1
fi
: > "$shadow/bison-invocations.tsv"

# Negative control 2: an absolute-path Bison invocation cannot bypass PATH.
printf '0 execve("/usr/bin/bison", ["bison", "parse.y"], ...) = 0\n' \
  >> "$shadow/build.execve"
if GITHUB_WORKSPACE=$root sh "$here/bison-guard.sh" verify "$root/gengtype-lex.cc" traced >/dev/null 2>&1; then
  echo 'an absolute-path Bison invocation was incorrectly accepted' >&2
  exit 1
fi

# Negative control 3: a generated file without an observed Flex call is not proof.
printf '0 execve("/usr/bin/make", ["make"], ...) = 0\n' \
  > "$shadow/build.execve"
if GITHUB_WORKSPACE=$root sh "$here/bison-guard.sh" verify "$root/gengtype-lex.cc" traced >/dev/null 2>&1; then
  echo 'a generated lexer without observed Flex was incorrectly accepted' >&2
  exit 1
fi
printf 'bootstrap guard: positive probe and three negative controls passed\n'
