/* Checked consumption of the maintained Idriç ICKY source protocol.
   Copyright (C) 2026 Free Software Foundation, Inc.
   This file is part of GCC, under the GNU GPL version 3 or later.

   This code reads located parser output, not ICK source grammar.  CPP owns
   the input token identities; ICKY owns syntax; GCC owns C interpretation.  */
#ifndef GCC_C_ICKY_PROTOCOL_H
#define GCC_C_ICKY_PROTOCOL_H

namespace icky_consumer {

enum class lexeme_kind { name, natural, glyph, opening, closing };
enum class node_kind { expression, group, name, natural, glyph };

struct lexeme
{
  lexeme_kind kind;
  std::string written;
  size_t beginning;
  size_t finishing;
};

struct source_span
{
  size_t character_beginning, starting_line, starting_column;
  size_t character_finishing, finishing_line, finishing_column;
  size_t byte_beginning, byte_finishing;
};

struct node
{
  node_kind kind;
  source_span span;
  std::string value;
  std::vector<node> children;
  size_t first_token, last_token;
  node () : kind (node_kind::expression), span (), first_token (0),
            last_token (0) {}
};

struct position
{
  size_t character, line, column;
  bool boundary;
  position () : character (0), line (0), column (0), boundary (false) {}
  position (size_t c, size_t l, size_t k)
    : character (c), line (l), column (k), boundary (true) {}
};

inline bool refusal (std::string &problem, const char *code)
{
  problem = code;
  return false;
}

inline bool count (const std::string &text, size_t &value)
{
  if (text.empty () || (text.size () > 1 && text[0] == '0'))
    return false;
  value = 0;
  for (size_t i = 0; i != text.size (); ++i)
    {
      unsigned digit = (unsigned char) text[i] - '0';
      if (digit > 9 || value > (1048576 - digit) / 10)
        return false;
      value = value * 10 + digit;
    }
  return true;
}

inline int hex_digit (char character)
{
  if (character >= '0' && character <= '9') return character - '0';
  if (character >= 'a' && character <= 'f') return character - 'a' + 10;
  return -1;
}

inline bool unhex (const std::string &text, std::string &bytes)
{
  bytes.clear ();
  if (text.size () % 2) return false;
  for (size_t i = 0; i != text.size (); i += 2)
    {
      int upper = hex_digit (text[i]), lower = hex_digit (text[i + 1]);
      if (upper < 0 || lower < 0) return false;
      bytes += char (upper * 16 + lower);
    }
  return true;
}

inline std::string hex (const std::string &bytes)
{
  static const char digits[] = "0123456789abcdef";
  std::string text;
  for (size_t i = 0; i != bytes.size (); ++i)
    {
      unsigned value = (unsigned char) bytes[i];
      text += digits[value / 16];
      text += digits[value % 16];
    }
  return text;
}

/* Strict scalar UTF-8.  Positions inside an encoding are never boundaries.  */
inline bool positions (const std::string &source, std::vector<position> &points)
{
  points.assign (source.size () + 1, position ());
  position current (0, 1, 1);
  points[0] = current;
  for (size_t i = 0; i < source.size (); )
    {
      unsigned first = (unsigned char) source[i];
      size_t width;
      if (first < 128) width = 1;
      else if (first >= 0xc2 && first <= 0xdf) width = 2;
      else if (first >= 0xe0 && first <= 0xef) width = 3;
      else if (first >= 0xf0 && first <= 0xf4) width = 4;
      else return false;
      if (width > source.size () - i) return false;
      for (size_t j = 1; j < width; ++j)
        if ((unsigned char) source[i + j] < 0x80
            || (unsigned char) source[i + j] > 0xbf) return false;
      if (width > 1)
        {
          unsigned second = (unsigned char) source[i + 1];
          if ((first == 0xe0 && second < 0xa0)
              || (first == 0xed && second > 0x9f)
              || (first == 0xf0 && second < 0x90)
              || (first == 0xf4 && second > 0x8f)) return false;
        }
      ++current.character;
      if (first == '\n') { ++current.line; current.column = 1; }
      else ++current.column;
      i += width;
      points[i] = current;
    }
  return true;
}

inline std::vector<std::string> fields (const std::string &line)
{
  std::vector<std::string> result;
  size_t beginning = 0;
  for (;;)
    {
      size_t separator = line.find ('\t', beginning);
      result.push_back (line.substr (beginning, separator - beginning));
      if (separator == std::string::npos) return result;
      beginning = separator + 1;
    }
}

class reader
{
  const std::string &source;
  const std::vector<lexeme> &tokens;
  std::vector<position> points;
  std::vector<std::vector<std::string> > rows;
  size_t next_row;
  std::string &problem;

  bool read_span (const std::vector<std::string> &row, source_span &span)
  {
    size_t values[8];
    if (row.size () < 10) return refusal (problem, "ICKY_PROTOCOL_FIELDS");
    for (size_t i = 0; i != 8; ++i)
      if (!count (row[i + 2], values[i]))
        return refusal (problem, "ICKY_SOURCE_SPAN");
    span.character_beginning = values[0]; span.starting_line = values[1];
    span.starting_column = values[2]; span.character_finishing = values[3];
    span.finishing_line = values[4]; span.finishing_column = values[5];
    span.byte_beginning = values[6]; span.byte_finishing = values[7];
    if (span.byte_beginning > span.byte_finishing
        || span.byte_finishing > source.size ())
      return refusal (problem, "ICKY_SOURCE_SPAN");
    const position &beginning = points[span.byte_beginning];
    const position &finishing = points[span.byte_finishing];
    if (!beginning.boundary || !finishing.boundary
        || beginning.character != span.character_beginning
        || beginning.line != span.starting_line
        || beginning.column != span.starting_column
        || finishing.character != span.character_finishing
        || finishing.line != span.finishing_line
        || finishing.column != span.finishing_column)
      return refusal (problem, "ICKY_SOURCE_SPAN");
    return true;
  }

  bool expression (const std::string &path, unsigned depth, node &result)
  {
    if (depth > 32 || next_row == rows.size ())
      return refusal (problem, "ICKY_AST_STRUCTURE");
    const std::vector<std::string> &row = rows[next_row++];
    if (row.size () != 10 || row[0] != "expr" || row[1] != path)
      return refusal (problem, "ICKY_AST_PATH");
    result.kind = node_kind::expression;
    if (!read_span (row, result.span)) return false;
    std::string prefix = path + ".";
    while (next_row != rows.size () && rows[next_row].size () > 1
           && rows[next_row][1].compare (0, prefix.size (), prefix) == 0)
      {
        node child;
        std::string expected = prefix + std::to_string (result.children.size ());
        if (!piece (expected, depth, child)) return false;
        result.children.push_back (child);
      }
    if (result.children.empty ()
        || result.children.back ().kind == node_kind::glyph
        || result.span.byte_beginning != result.children.front ().span.byte_beginning
        || result.span.byte_finishing != result.children.back ().span.byte_finishing)
      return refusal (problem, "ICKY_AST_STRUCTURE");
    return true;
  }

  bool piece (const std::string &path, unsigned depth, node &result)
  {
    if (depth > 32 || next_row == rows.size ())
      return refusal (problem, "ICKY_AST_STRUCTURE");
    const std::vector<std::string> &row = rows[next_row++];
    if (row.size () < 2 || row[1] != path)
      return refusal (problem, "ICKY_AST_PATH");
    if (!read_span (row, result.span)) return false;
    if (row[0] == "group")
      {
        result.kind = node_kind::group;
        if (row.size () != 10) return refusal (problem, "ICKY_PROTOCOL_FIELDS");
        node nested;
        if (!expression (path, depth + 1, nested)) return false;
        result.children.push_back (nested);
        return true;
      }
    if (row.size () != 12) return refusal (problem, "ICKY_PROTOCOL_FIELDS");
    if (row[0] == "name") result.kind = node_kind::name;
    else if (row[0] == "natural") result.kind = node_kind::natural;
    else if (row[0] == "glyph") result.kind = node_kind::glyph;
    else return refusal (problem, "ICKY_PROTOCOL_RECORD");
    std::string written;
    if (!unhex (row[11], written)
        || written != source.substr (result.span.byte_beginning,
                                     result.span.byte_finishing - result.span.byte_beginning))
      return refusal (problem, "ICKY_SOURCE_SPELLING");
    result.value = row[10];
    return true;
  }

  bool coverage (node &value, size_t &next_token)
  {
    value.first_token = next_token;
    if (value.kind == node_kind::expression)
      {
        for (size_t i = 0; i != value.children.size (); ++i)
          if (!coverage (value.children[i], next_token)) return false;
      }
    else if (value.kind == node_kind::group)
      {
        if (next_token == tokens.size ()
            || tokens[next_token].kind != lexeme_kind::opening
            || tokens[next_token].beginning != value.span.byte_beginning)
          return refusal (problem, "ICKY_SOURCE_MAP");
        ++next_token;
        if (!coverage (value.children[0], next_token)) return false;
        if (next_token == tokens.size ()
            || tokens[next_token].kind != lexeme_kind::closing
            || tokens[next_token].finishing != value.span.byte_finishing)
          return refusal (problem, "ICKY_SOURCE_MAP");
        ++next_token;
      }
    else
      {
        if (next_token == tokens.size ())
          return refusal (problem, "ICKY_SOURCE_MAP");
        const lexeme &token = tokens[next_token];
        if (token.beginning != value.span.byte_beginning
            || token.finishing != value.span.byte_finishing)
          return refusal (problem, "ICKY_SOURCE_MAP");
        bool matching_kind = (value.kind == node_kind::name && token.kind == lexeme_kind::name)
          || (value.kind == node_kind::natural && token.kind == lexeme_kind::natural)
          || (value.kind == node_kind::glyph && token.kind == lexeme_kind::glyph);
        if (!matching_kind) return refusal (problem, "ICKY_SOURCE_MAP");
        if (value.kind == node_kind::natural)
          {
            for (size_t i = 0; i != token.written.size (); ++i)
              if (token.written[i] < '0' || token.written[i] > '9')
                return refusal (problem, "ICKY_LITERAL_BOUNDARY");
            size_t significant = token.written.find_first_not_of ('0');
            std::string decimal = significant == std::string::npos
              ? "0" : token.written.substr (significant);
            if (value.value != decimal)
              return refusal (problem, "ICKY_LITERAL_VALUE");
          }
        else if (value.value != token.written)
          return refusal (problem, "ICKY_SOURCE_SPELLING");
        ++next_token;
      }
    if (next_token == value.first_token)
      return refusal (problem, "ICKY_AST_STRUCTURE");
    value.last_token = next_token - 1;
    if (tokens[value.first_token].beginning != value.span.byte_beginning
        || tokens[value.last_token].finishing != value.span.byte_finishing)
      return refusal (problem, "ICKY_SOURCE_MAP");
    return true;
  }

public:
  reader (const std::string &input, const std::vector<lexeme> &bindings,
          std::string &diagnostic)
    : source (input), tokens (bindings), next_row (0), problem (diagnostic) {}

  bool decode (const std::string &stream, node &root)
  {
    rows.clear ();
    next_row = 0;
    root = node ();
    if (source.empty () || source.size () > 65536 || tokens.size () > 512
        || stream.empty () || stream.size () > 1048576 || stream.back () != '\n')
      return refusal (problem, "ICKY_PROTOCOL_BOUNDARY");
    if (!positions (source, points)) return refusal (problem, "ICKY_SOURCE_UTF8");
    size_t offset = 0;
    for (size_t i = 0; i != tokens.size (); ++i)
      {
        if (i) ++offset;
        const lexeme &token = tokens[i];
        if (token.written.empty () || token.beginning != offset
            || token.finishing != offset + token.written.size ()
            || token.finishing > source.size ()
            || !points[token.beginning].boundary || !points[token.finishing].boundary
            || source.compare (token.beginning, token.written.size (), token.written) != 0
            || (i && source[token.beginning - 1] != ' '))
          return refusal (problem, "ICKY_SOURCE_MAP");
        offset = token.finishing;
      }
    if (offset != source.size ()) return refusal (problem, "ICKY_SOURCE_MAP");
    size_t beginning = 0;
    while (beginning < stream.size ())
      {
        size_t finishing = stream.find ('\n', beginning);
        if (finishing == std::string::npos || rows.size () > 4096)
          return refusal (problem, "ICKY_PROTOCOL_BOUNDARY");
        rows.push_back (fields (stream.substr (beginning, finishing - beginning)));
        beginning = finishing + 1;
      }
    if (rows.size () < 4 || rows[0].size () != 3
        || rows[0][0] != "ICKY-LOCATED" || rows[0][1] != "3"
        || rows[0][2] != "char-and-utf8-byte-offset")
      return refusal (problem, "ICKY_PROTOCOL_VERSION");
    size_t character_count, byte_count;
    std::string framed;
    if (rows[1].size () != 4 || rows[1][0] != "source"
        || !count (rows[1][1], character_count) || !count (rows[1][2], byte_count)
        || byte_count != source.size () || character_count != points.back ().character
        || !unhex (rows[1][3], framed) || framed != source)
      return refusal (problem, "ICKY_SOURCE_FRAME");
    if (rows[2].size () != 2 || rows[2][0] != "ok" || rows[2][1] != "1")
      return refusal (problem, "ICKY_AST_RESULT");
    next_row = 3;
    if (!expression ("0", 0, root)) return false;
    if (next_row != rows.size ()) return refusal (problem, "ICKY_PROTOCOL_TRAILING");
    size_t next_token = 0;
    if (!coverage (root, next_token)) return false;
    if (next_token != tokens.size ()) return refusal (problem, "ICKY_SOURCE_MAP");
    return true;
  }
};

struct plan
{
  bool assignment;
  size_t target, operation, value;
  plan () : assignment (false), target (0), operation (0), value (0) {}
};

inline const node *noun (const node &value)
{
  if (value.kind == node_kind::name || value.kind == node_kind::natural)
    return &value;
  if (value.kind == node_kind::group && value.children.size () == 1
      && value.children[0].children.size () == 1)
    return noun (value.children[0].children[0]);
  return NULL;
}

inline bool admitted_plan (const node &root, plan &result, std::string &problem)
{
  result = plan ();
  const node *value = NULL;
  if (root.children.size () == 1)
    value = noun (root.children[0]);
  else if (root.children.size () == 3
           && root.children[0].kind == node_kind::name
           && root.children[1].kind == node_kind::glyph
           && root.children[1].value == "\xe2\x86\x90")
    {
      result.assignment = true;
      result.target = root.children[0].first_token;
      result.operation = root.children[1].first_token;
      value = noun (root.children[2]);
    }
  if (!value) return refusal (problem, "ICKY_AST_UNSUPPORTED");
  result.value = value->first_token;
  return true;
}

} /* namespace icky_consumer */
#endif
