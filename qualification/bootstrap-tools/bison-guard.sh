#!/bin/sh
# C-only ICK bootstrap: distinguish configure probes from generator use.
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
guard_dir=${ICK_BOOTSTRAP_GUARD_DIR:-${GITHUB_WORKSPACE:-$repository_root}/.ick-bootstrap-guard}
log=$guard_dir/bison-invocations.tsv

case ${1:-} in
  setup)
    materialized_source=${2:?pass the materialized source directory}
    test -d "$materialized_source/gcc/c"
    test ! -e "$materialized_source/gcc/cobol"
    test ! -e "$materialized_source/libgcobol"
    test -s "$materialized_source/gcc/gengtype-lex.l"
    test -s "$materialized_source/gcc/gengtype-parse.cc"
    test ! -e "$materialized_source/gcc/gengtype-lex.cc"
    grep -Fq 'gengtype-lex.cc : gengtype-lex.l' \
      "$materialized_source/gcc/Makefile.in"
    flex_executable=$(command -v flex)
    test -n "$flex_executable"
    "$flex_executable" --version

    mkdir -p "$guard_dir"
    : > "$log"
    cat > "$guard_dir/bison" <<'SHADOW'
#!/bin/sh
set -eu
case "$*" in
  --version|-V|--help|'-y --version'|'--version -y') category=probe ;;
  *) category=use ;;
esac
printf '%s\t%s\t%s\t%s\n' \
  "$category" "${0##*/}" "${ICK_BOOTSTRAP_PHASE:-unclassified}" "$*" \
  >> "${ICK_BISON_LOG:?missing ICK_BISON_LOG}"
# Even configure-only probes get a negative result: no usable Bison or Yacc.
exit 86
SHADOW
    chmod 0755 "$guard_dir/bison"
    ln -s bison "$guard_dir/yacc"
    if test -n "${GITHUB_ENV:-}" && test -n "${GITHUB_PATH:-}"; then
      {
        printf 'BISON=%s/bison\n' "$guard_dir"
        printf 'YACC=%s/yacc\n' "$guard_dir"
        printf 'ICK_BISON_LOG=%s\n' "$log"
      } >> "$GITHUB_ENV"
      printf '%s\n' "$guard_dir" >> "$GITHUB_PATH"
    else
      printf 'export PATH=%s:$PATH\n' "$guard_dir"
      printf 'export BISON=%s/bison YACC=%s/yacc ICK_BISON_LOG=%s\n' \
        "$guard_dir" "$guard_dir" "$log"
    fi
    ;;
  verify)
    generated=${2:?pass the built gengtype-lex.cc path}
    test -s "$generated" || {
      printf 'no generated gengtype lexer: %s\n' "$generated" >&2
      exit 1
    }
    test -f "$log" || {
      echo 'Bison shadow invocation log is absent' >&2
      exit 1
    }
    if grep "^use$(printf '\t')" "$log"; then
      echo 'Bison/Yacc was invoked for generation, not merely detected' >&2
      exit 1
    fi
    if test "${3:-}" = traced; then
      for phase in configure build install; do
        test -s "$guard_dir/$phase.execve" || {
          printf 'missing process trace: %s\n' "$phase" >&2
          exit 1
        }
      done
      # These traces cover configure/build/install descendants. An absolute
      # Bison/Yacc executable bypass is prohibited, not reclassified as ICKY.
      if grep -Eh 'execve\("(/[^"[:space:]]*/)?(bison|yacc)"' \
        "$guard_dir"/*.execve | grep -Fv "$guard_dir/"; then
        echo 'Bison/Yacc execution bypassed the shadow' >&2
        exit 1
      fi
      if ! grep -E 'execve\("(/[^"[:space:]]*/)?flex"' \
          "$guard_dir/build.execve" | grep -F 'gengtype-lex.cc' > /dev/null; then
        echo 'no traced Flex invocation generated gengtype-lex.cc' >&2
        exit 1
      fi
    fi
    printf 'PASS: COBOL pruned; generated gengtype lexer present; Bison/Yacc generation not observed\n'
    printf 'Bison/Yacc probe log:\n'
    cat "$log"
    sha256sum "$generated"
    ;;
  *)
    echo 'usage: sh bison-guard.sh setup MATERIALIZED_SOURCE | verify GENERATED_LEXER [traced]' >&2
    exit 2
    ;;
esac
