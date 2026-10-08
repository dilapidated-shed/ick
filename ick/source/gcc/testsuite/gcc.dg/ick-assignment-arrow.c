/* { dg-do run } */
/* { dg-options "-std=c11 -O2 -Wall -Wextra -Werror" } */

/* An executable oracle for ICK's C assignment glyph.  Every nonzero
   result identifies a different semantic or lexical failure. */

#define ASSIGN ←
#define STORE(destination, source) ((destination) ← (source))
#define STRINGIFY_INNER(value) #value
#define STRINGIFY(value) STRINGIFY_INNER(value)

struct AppendAddress {
  unsigned stream;
  unsigned offset;
};

enum extent_kind { allocated ← 1, written ← 2 };
_Static_assert (u'←' == 0x2190, "character literal was changed");

static int
same_bytes (const char *left, const char *right)
{
  for (unsigned index ← 0; ; ++index)
    {
      if (left[index] != right[index])
        return 0;
      if (left[index] == '\0')
        return 1;
    }
}

static int
next_value (unsigned *call_count)
{
  *call_count ← *call_count + 1;
  return 19;
}

int
main (void)
{
  struct AppendAddress address ← { .stream ← 7, .offset ← 0 };
  struct AppendAddress *address_pointer ← &address;
  unsigned values[3] ← { 0, 0, 0 };
  unsigned destination_index ← 0;
  unsigned call_count ← 0;
  unsigned first ← 0;
  unsigned second ← 0;

  address_pointer->offset ← 11;
  if (address.stream != 7 || address.offset != 11)
    return 1;

  values[destination_index++] ← next_value (&call_count);
  if (destination_index != 1 || call_count != 1 || values[0] != 19)
    return 2;

  first ← second ← 23;
  if (first != 23 || second != 23)
    return 3;

  first ASSIGN 29;
  if (STORE (second, first + 2) != 31 || second != 31)
    return 4;

  for (unsigned index ← 0; index < 3; ++index)
    values[index] ← index + 1;
  if (values[0] != 1 || values[1] != 2 || values[2] != 3)
    return 5;

  /* Literal ← and comments ← retain their original bytes. */
  if (!same_bytes ("←", "\xe2\x86\x90"))
    return 6;
  if (!same_bytes (STRINGIFY (ASSIGN), "\xe2\x86\x90"))
    return 7;
  if (!same_bytes (STRINGIFY_INNER (←), "\xe2\x86\x90"))
    return 8;

  /* Ordinary C remains available for unmodified foreign source. */
  first = 37;
  second += 2;
  if (first != 37 || second != 33 || allocated != 1 || written != 2)
    return 9;

  return 0;
}
