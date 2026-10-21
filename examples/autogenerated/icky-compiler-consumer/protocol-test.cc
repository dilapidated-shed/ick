/* Exercise the GCC foreign protocol boundary with the maintained parser's
   output. This does not implement or substitute ICKY grammar. */
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "../../../ick/source/gcc/c/icky-protocol.h"

using namespace icky_consumer;
static unsigned assertions;
static void check (bool condition, const char *name)
{
  if (!condition) { fprintf (stderr, "FAIL\t%s\n", name); exit (1); }
  ++assertions;
  printf ("PASS\t%s\n", name);
}
static std::string read (const char *path)
{
  FILE *file = fopen (path, "rb");
  if (!file) exit (2);
  std::string bytes;
  char buffer[4096]; size_t amount;
  while ((amount = fread (buffer, 1, sizeof buffer, file))) bytes.append (buffer, amount);
  if (ferror (file) || fclose (file)) exit (2);
  return bytes;
}
static std::string replace (std::string text, const std::string &from,
                            const std::string &to)
{
  size_t at = text.find (from);
  if (at == std::string::npos) exit (2);
  text.replace (at, from.size (), to);
  return text;
}
static bool consume (const std::string &source, const std::vector<lexeme> &tokens,
                     const std::string &protocol, std::string &problem, plan &meaning)
{
  problem.clear ();
  reader decoder (source, tokens, problem);
  node syntax;
  return decoder.decode (protocol, syntax) && admitted_plan (syntax, meaning, problem);
}
int main (int argc, char **argv)
{
  if (argc != 3) return 2;
  std::string source = read (argv[1]), protocol = read (argv[2]), problem;
  check (source == "x ← ( 010 )", "canonical-fixture");
  std::vector<lexeme> tokens = {
    {lexeme_kind::name, "x", 0, 1},
    {lexeme_kind::glyph, "←", 2, 5},
    {lexeme_kind::opening, "(", 6, 7},
    {lexeme_kind::natural, "010", 8, 11},
    {lexeme_kind::closing, ")", 12, 13}
  };
  plan meaning;
  check (consume (source, tokens, protocol, problem, meaning), "maintained-parser-output");
  check (meaning.assignment && meaning.target == 0 && meaning.operation == 1
         && meaning.value == 3, "checked-AST-selects-original-CPP-operands");
  check (!consume (source, tokens, "", problem, meaning)
         && problem == "ICKY_PROTOCOL_BOUNDARY", "no-op-parser");
  check (!consume (source, tokens, protocol.substr (0, protocol.size () - 1), problem, meaning),
         "truncated-protocol");
  check (!consume (source, tokens, protocol + "warning\tignored\n", problem, meaning),
         "unexpected-record");
  check (!consume (source, tokens, replace (protocol, "7820e28690", "7920e28690"), problem, meaning)
         && problem == "ICKY_SOURCE_FRAME", "different-complete-source-frame");
  check (!consume (source, tokens, replace (protocol, "\t10\t303130", "\t8\t303130"), problem, meaning)
         && problem == "ICKY_LITERAL_VALUE", "Nat-is-not-C-octal-value");
  check (!consume (source, tokens, replace (protocol, "\t10\t303130", "\t10\t3130"), problem, meaning)
         && problem == "ICKY_SOURCE_SPELLING", "lost-leading-zero-spelling");
  check (!consume (source, tokens, replace (protocol, "natural\t0.2.0", "natural\t0.2.1"), problem, meaning),
         "reordered-AST-path");
  const std::string glyph = "glyph\t0.1\t2\t1\t3\t3\t1\t4\t2\t5\t←\te28690";
  std::vector<std::string> columns = fields (glyph);
  for (unsigned coordinate = 2; coordinate != 10; ++coordinate)
    {
      std::string changed;
      for (unsigned i = 0; i != columns.size (); ++i)
        { if (i) changed += '\t'; changed += i == coordinate ? "99" : columns[i]; }
      check (!consume (source, tokens, replace (protocol, glyph, changed), problem, meaning)
             && problem == "ICKY_SOURCE_SPAN", "all-eight-UTF8-coordinates-bound");
    }
  std::vector<lexeme> changed = tokens;
  changed[3].beginning = 7;
  check (!consume (source, changed, protocol, problem, meaning)
         && problem == "ICKY_SOURCE_MAP", "changed-compiler-map");
  changed = tokens; changed[1].written = "↚";
  check (!consume (source, changed, protocol, problem, meaning), "neighboring-glyph-not-substituted");
  std::string equal_source = replace (source, "←", "=");
  changed = {{lexeme_kind::name,"x",0,1},{lexeme_kind::glyph,"=",2,3},
             {lexeme_kind::opening,"(",4,5},{lexeme_kind::natural,"010",6,9},
             {lexeme_kind::closing,")",10,11}};
  check (!consume (equal_source, changed, protocol, problem, meaning), "ASCII-rewrite-not-source-identity");
  check (!consume (std::string ("\xc0\xaf"), tokens, protocol, problem, meaning)
         && problem == "ICKY_SOURCE_UTF8", "non-scalar-UTF8");
  printf ("assertions\t%u\n", assertions);
}
