/* GCC semantic adapter for the maintained Idriç ICKY parser.
   Copyright (C) 2026 Free Software Foundation, Inc.
   This file is part of GCC, under the GNU GPL version 3 or later.

   Included after the existing C parser's token and semantic interfaces.
   This is a foreign compiler boundary, not a second ICK source parser.  */
#ifndef GCC_C_ICKY_CONSUMER_H
#define GCC_C_ICKY_CONSUMER_H

#include "icky-protocol.h"

namespace icky_compiler {

struct raw_source
{
  std::string path, bytes;
};

struct source_point
{
  size_t source, byte;
  unsigned line, column;
};

struct token_mapping
{
  c_token token;
  source_point spelling, expansion;
};

inline bool read_source (const std::string &path, std::string &bytes)
{
  FILE *input = fopen (path.c_str (), "rb");
  if (!input) return false;
  bytes.clear ();
  char buffer[4096];
  size_t amount;
  bool complete = true;
  while ((amount = fread (buffer, 1, sizeof buffer, input)) != 0)
    {
      if (bytes.size () + amount > 1048576) { complete = false; break; }
      bytes.append (buffer, amount);
    }
  if (ferror (input)) complete = false;
  if (fclose (input)) complete = false;
  return complete;
}

/* Use CPP's actual spelling and expansion locations, and require their real
   file snapshots.  Fabricated #line files, generated/pasted tokens without a
   unique written slice, and unavailable maps are explicit boundaries.  */
inline bool locate (location_t location, std::vector<raw_source> &sources,
                    source_point &point, std::string &problem)
{
  expanded_location expanded = expand_location (location);
  if (!expanded.file || expanded.file[0] == '<'
      || expanded.line <= 0 || expanded.column <= 0)
    return icky_consumer::refusal (problem, "ICKY_SOURCE_LOCATION");
  char *resolved = lrealpath (expanded.file);
  if (!resolved) return icky_consumer::refusal (problem, "ICKY_SOURCE_LOCATION");
  std::string path (resolved);
  free (resolved);
  size_t ordinal = 0;
  while (ordinal < sources.size () && sources[ordinal].path != path) ++ordinal;
  if (ordinal == sources.size ())
    {
      if (sources.size () >= 32)
        return icky_consumer::refusal (problem, "ICKY_SOURCE_RESOURCE");
      raw_source snapshot;
      snapshot.path = path;
      if (!read_source (path, snapshot.bytes))
        return icky_consumer::refusal (problem, "ICKY_SOURCE_UNAVAILABLE");
      size_t total = snapshot.bytes.size ();
      for (size_t i = 0; i != sources.size (); ++i) total += sources[i].bytes.size ();
      if (total > 8 * 1048576)
        return icky_consumer::refusal (problem, "ICKY_SOURCE_RESOURCE");
      sources.push_back (snapshot);
    }
  const std::string &bytes = sources[ordinal].bytes;
  size_t beginning = 0;
  for (int line = 1; line < expanded.line; ++line)
    {
      beginning = bytes.find ('\n', beginning);
      if (beginning == std::string::npos)
        return icky_consumer::refusal (problem, "ICKY_SOURCE_LOCATION");
      ++beginning;
    }
  size_t finishing = bytes.find ('\n', beginning);
  if (finishing == std::string::npos) finishing = bytes.size ();
  if ((size_t) expanded.column > finishing - beginning + 1)
    return icky_consumer::refusal (problem, "ICKY_SOURCE_LOCATION");
  point.source = ordinal;
  point.byte = beginning + expanded.column - 1;
  point.line = expanded.line;
  point.column = expanded.column;
  if (point.byte >= bytes.size ())
    return icky_consumer::refusal (problem, "ICKY_SOURCE_LOCATION");
  return true;
}

inline bool capture (const c_token &token, std::vector<raw_source> &sources,
                     token_mapping &mapping, std::string &problem)
{
  if (!token.source_spelling || !token.source_spelling_length
      || token.source_spelling_length > 65536)
    return icky_consumer::refusal (problem, "ICKY_TOKEN_UNSUPPORTED");
  location_t original = get_pure_location (token.location);
  const line_map_ordinary *map = NULL;
  location_t spelling = linemap_resolve_location (line_table, original,
                                                 LRK_SPELLING_LOCATION, &map);
  location_t expansion = linemap_resolve_location (line_table, original,
                                                  LRK_MACRO_EXPANSION_POINT, &map);
  mapping.token = token;
  if (!locate (spelling, sources, mapping.spelling, problem)
      || !locate (expansion, sources, mapping.expansion, problem)) return false;
  const std::string &bytes = sources[mapping.spelling.source].bytes;
  if (token.source_spelling_length > bytes.size () - mapping.spelling.byte
      || bytes.compare (mapping.spelling.byte, token.source_spelling_length,
                        token.source_spelling, token.source_spelling_length) != 0)
    return icky_consumer::refusal (problem, "ICKY_EXPANSION_MAP");
  return true;
}

inline bool unchanged (const std::vector<raw_source> &sources, std::string &problem)
{
  for (size_t i = 0; i != sources.size (); ++i)
    {
      std::string observed;
      if (!read_source (sources[i].path, observed) || observed != sources[i].bytes)
        return icky_consumer::refusal (problem, "ICKY_SOURCE_CHANGED");
    }
  return true;
}

inline bool run_parser (const std::string &source, std::string &output,
                        std::vector<std::string> &arguments, std::string &problem)
{
  bool packaged = ick_icky_parser_package && ick_icky_parser_package[0];
  bool direct = ick_icky_parser && ick_icky_parser[0];
  if (packaged == direct)
    return icky_consumer::refusal (problem, "ICKY_SELECT_ONE_PARSER");
  std::string provider = packaged ? ick_icky_parser_package : ick_icky_parser;
  if (!IS_ABSOLUTE_PATH (provider.c_str ()))
    return icky_consumer::refusal (problem, "ICKY_ABSOLUTE_PARSER_REQUIRED");
  char *temporary = make_temp_file (".icky");
  FILE *input = fopen (temporary, "wb");
  if (!input)
    { free (temporary); return icky_consumer::refusal (problem, "ICKY_INPUT_IO"); }
  bool written = fwrite (source.data (), 1, source.size (), input) == source.size ();
  if (fclose (input)) written = false;
  if (!written)
    {
      unlink (temporary); free (temporary);
      return icky_consumer::refusal (problem, "ICKY_INPUT_IO");
    }
  std::vector<std::string> environment;
  environment.push_back ("LC_ALL=C.UTF-8");
  environment.push_back ("LANG=C.UTF-8");
  if (packaged)
    {
#if !defined (__linux__) || !defined (__x86_64__)
      unlink (temporary); free (temporary);
      return icky_consumer::refusal (problem, "ICKY_PACKAGE_HOST_UNSUPPORTED");
#else
      /* This is the package's declared native ABI, byte-for-byte the same
         loader/runtime/app selection as its separate Grease harness.
         Do not rebuild a parser, inherit host Scheme, or invoke a shell.  */
      std::string application = provider + "/app/icky-parser_app";
      std::string libraries = provider + "/runtime/elf:" + application;
      arguments.push_back (provider + "/runtime/elf/ld-linux-x86-64.so.2");
      arguments.push_back ("--library-path"); arguments.push_back (libraries);
      arguments.push_back (provider + "/runtime/scheme");
      arguments.push_back ("-b"); arguments.push_back (provider + "/runtime/petite.boot");
      arguments.push_back ("-b"); arguments.push_back (provider + "/runtime/scheme.boot");
      arguments.push_back ("--program");
      arguments.push_back (application + "/icky-parser.so");
      environment.push_back ("LD_LIBRARY_PATH=" + libraries);
      environment.push_back ("IDRIS2_INC_SRC=" + application);
#endif
    }
  else arguments.push_back (provider);
  arguments.push_back ("--parse-v3"); arguments.push_back (temporary);
  std::vector<char *> argv, envp;
  for (size_t i = 0; i != arguments.size (); ++i)
    argv.push_back (const_cast<char *> (arguments[i].c_str ()));
  for (size_t i = 0; i != environment.size (); ++i)
    envp.push_back (const_cast<char *> (environment[i].c_str ()));
  argv.push_back (NULL); envp.push_back (NULL);
  pex_obj *process = pex_init (PEX_USE_PIPES, progname, NULL);
  int process_error = 0;
  const char *failure = pex_run_in_environment (process, PEX_STDERR_TO_STDOUT,
                                               argv[0], &argv[0], &envp[0],
                                               NULL, NULL, &process_error);
  bool accepted = !failure;
  output.clear ();
  FILE *stream = accepted ? pex_read_output (process, 1) : NULL;
  if (!stream) accepted = false;
  if (stream)
    {
      char buffer[4096];
      size_t amount;
      while ((amount = fread (buffer, 1, sizeof buffer, stream)) != 0)
        {
          if (output.size () + amount > 1048576) { accepted = false; break; }
          output.append (buffer, amount);
        }
      if (ferror (stream)) accepted = false;
    }
  int status = -1;
  if (accepted && (!pex_get_status (process, 1, &status) || status != 0))
    accepted = false;
  pex_free (process);
  unlink (temporary); free (temporary);
  if (!accepted) return icky_consumer::refusal (problem, "ICKY_PARSER_EXECUTION");
  return true;
}

inline bool receipt (const std::vector<raw_source> &sources,
                     const std::vector<token_mapping> &mappings,
                     const std::vector<icky_consumer::lexeme> &bindings,
                     const std::string &source, const std::string &protocol,
                     const std::vector<std::string> &arguments,
                     std::string &problem)
{
  if (!ick_icky_receipt || !ick_icky_receipt[0]) return true;
  char *resolved = lrealpath (ick_icky_receipt);
  if (resolved)
    {
      for (size_t i = 0; i != sources.size (); ++i)
        if (sources[i].path == resolved)
          {
            free (resolved);
            return icky_consumer::refusal (problem, "ICKY_RECEIPT_INPUT_COLLISION");
          }
      free (resolved);
    }
  FILE *record = fopen (ick_icky_receipt, "ab");
  if (!record) return icky_consumer::refusal (problem, "ICKY_RECEIPT_IO");
  fprintf (record, "ICK-ICKY-CONSUMER\t1\n");
  for (size_t i = 0; i != sources.size (); ++i)
    fprintf (record, "raw\t%zu\t%s\t%zu\t%s\n", i,
             icky_consumer::hex (sources[i].path).c_str (), sources[i].bytes.size (),
             icky_consumer::hex (sources[i].bytes).c_str ());
  fprintf (record, "parsed\t%zu\t%s\n", source.size (),
           icky_consumer::hex (source).c_str ());
  for (size_t i = 0; i != mappings.size (); ++i)
    {
      const token_mapping &mapping = mappings[i];
      fprintf (record, "map\t%zu\t%zu\t%zu\t%s\t%zu\t%zu\t%u\t%u\t%zu\t%zu\t%u\t%u\n",
               i, bindings[i].beginning, bindings[i].finishing,
               icky_consumer::hex (bindings[i].written).c_str (),
               mapping.spelling.source, mapping.spelling.byte,
               mapping.spelling.line, mapping.spelling.column,
               mapping.expansion.source, mapping.expansion.byte,
               mapping.expansion.line, mapping.expansion.column);
    }
  for (size_t i = 0; i < arguments.size (); ++i)
    fprintf (record, "argv\t%zu\t%s\n", i,
             icky_consumer::hex (arguments[i]).c_str ());
  fprintf (record, "protocol\t%zu\t%s\nsyntax-accepted\t1\n",
           protocol.size (), icky_consumer::hex (protocol).c_str ());
  bool complete = !ferror (record);
  if (fclose (record)) complete = false;
  if (!complete) return icky_consumer::refusal (problem, "ICKY_RECEIPT_IO");
  return true;
}

inline c_expr bound_noun (const c_token &token)
{
  c_expr result;
  result.original_code = ERROR_MARK;
  result.original_type = NULL_TREE;
  result.m_decimal = token.flags & DECIMAL_INT;
  if (token.type == CPP_NAME)
    result.value = build_external_ref (token.location, token.value, false,
                                       &result.original_type);
  else result.value = token.value;
  set_c_expr_source_range (&result, token.get_range ());
  return result;
}

} /* namespace icky_compiler */

static c_expr
c_parser_icky_expression (c_parser *parser)
{
  location_t beginning = c_parser_peek_token (parser)->location;
  location_t finishing = beginning;
  c_expr result;
  result.set_error ();
  result.original_code = ERROR_MARK; result.original_type = NULL_TREE;
  result.m_decimal = 0;
  result.src_range.m_start = result.src_range.m_finish = beginning;
  c_parser_consume_token (parser);
  if (!c_parser_require (parser, CPP_OPEN_PAREN, "expected %<(%> after %<__builtin_icky%>"))
    return result;
  std::vector<c_token> tokens;
  std::vector<icky_compiler::raw_source> sources;
  std::vector<icky_compiler::token_mapping> mappings;
  std::vector<icky_consumer::lexeme> bindings;
  std::string source, problem;
  unsigned depth = 0;
  bool closed = false;
  if ((!ick_icky_parser || !ick_icky_parser[0])
      && (!ick_icky_parser_package || !ick_icky_parser_package[0]))
    problem = "ICKY_PARSER_REQUIRED";
  while (c_parser_next_token_is_not (parser, CPP_EOF))
    {
      c_token token = *c_parser_peek_token (parser);
      if (token.type == CPP_PRAGMA || token.type == CPP_PRAGMA_EOL)
        { problem = "ICKY_TOKEN_UNSUPPORTED"; break; }
      if (token.type == CPP_CLOSE_PAREN && depth == 0)
        {
          finishing = token.get_finish ();
          c_parser_consume_token (parser); closed = true; break;
        }
      if (token.type == CPP_OPEN_PAREN) ++depth;
      if (token.type == CPP_CLOSE_PAREN) --depth;
      c_parser_consume_token (parser);
      if (!problem.empty ()) continue;
      if (tokens.size () == 512 || depth > 32)
        { problem = "ICKY_INPUT_BOUNDARY"; continue; }
      icky_compiler::token_mapping mapping;
      if (!icky_compiler::capture (token, sources, mapping, problem)) continue;
      icky_consumer::lexeme binding;
      if (token.type == CPP_NAME && token.id_kind == C_ID_ID)
        binding.kind = icky_consumer::lexeme_kind::name;
      else if (token.type == CPP_NUMBER && token.value
               && TREE_CODE (token.value) == INTEGER_CST)
        binding.kind = icky_consumer::lexeme_kind::natural;
      else if (token.type == CPP_EQ) binding.kind = icky_consumer::lexeme_kind::glyph;
      else if (token.type == CPP_OPEN_PAREN) binding.kind = icky_consumer::lexeme_kind::opening;
      else if (token.type == CPP_CLOSE_PAREN) binding.kind = icky_consumer::lexeme_kind::closing;
      else { problem = "ICKY_TOKEN_UNSUPPORTED"; continue; }
      binding.written.assign (token.source_spelling, token.source_spelling_length);
      if (!tokens.empty ()) source += ' ';
      binding.beginning = source.size (); source += binding.written;
      binding.finishing = source.size ();
      if (source.size () > 65536) { problem = "ICKY_INPUT_BOUNDARY"; continue; }
      tokens.push_back (token); mappings.push_back (mapping); bindings.push_back (binding);
    }
  if (!closed && problem.empty ()) problem = "ICKY_UNTERMINATED_INPUT";
  std::string protocol;
  std::vector<std::string> arguments;
  icky_consumer::node syntax;
  icky_consumer::plan meaning;
  if (problem.empty ())
    icky_compiler::run_parser (source, protocol, arguments, problem);
  if (problem.empty ())
    icky_compiler::unchanged (sources, problem);
  if (problem.empty ())
    {
      icky_consumer::reader decoder (source, bindings, problem);
      decoder.decode (protocol, syntax);
    }
  if (problem.empty ()) icky_consumer::admitted_plan (syntax, meaning, problem);
  if (problem.empty ())
    icky_compiler::receipt (sources, mappings, bindings, source, protocol, arguments, problem);
  if (!problem.empty ())
    {
      error_at (beginning, "ICKY source lane refused: %s", problem.c_str ());
      return result;
    }
  result = icky_compiler::bound_noun (tokens[meaning.value]);
  if (meaning.assignment && result.value != error_mark_node)
    {
      c_expr target = icky_compiler::bound_noun (tokens[meaning.target]);
      result = convert_lvalue_to_rvalue (result.get_location (), result, true, true);
      result.value = build_modify_expr (tokens[meaning.operation].location,
                                        target.value, target.original_type, NOP_EXPR,
                                        result.get_location (), result.value,
                                        result.original_type);
      result.original_code = MODIFY_EXPR;
      result.original_type = NULL_TREE; result.m_decimal = 0;
    }
  set_c_expr_source_range (&result, beginning, finishing);
  return result;
}
#endif
