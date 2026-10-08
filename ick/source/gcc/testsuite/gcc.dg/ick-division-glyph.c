/* { dg-do run } */
/* { dg-options "-std=c11 -O2 -Wall -Wextra -Werror" } */
#define QUOTIENT(left, right) ((left) ÷ (right))
#define STRINGIFY_INNER(value) #value
#define STRINGIFY(value) STRINGIFY_INNER(value)

static int same_bytes(const char *left, const char *right)
{
  for (unsigned index ← 0; ; ++index)
    {
      if (left[index] != right[index]) return 0;
      if (left[index] == '\0') return 1;
    }
}
static unsigned next_divisor(unsigned *calls)
{
  ++*calls;
  return 3;
}
int main(void)
{
  unsigned calls ← 0;
  unsigned quotient ← QUOTIENT(24, next_divisor(&calls));
  if (calls != 1 || quotient != 8) return 1;
  if (24 ÷ 3 × 2 != 16 || 24 ÷ 3 ÷ 2 != 4) return 2;
  if (2 + 12 ÷ 3 != 6 || 7 ÷ 3 != 2) return 3;
  if (-7 ÷ 3 != -2 || 7.5 ÷ 2.5 != 3.0) return 4;
  int value ← 18;
  int *pointer ← &value;
  if (*pointer ÷ 3 != 6) return 5;
  if (!same_bytes("÷", "\xc3\xb7")) return 6;
  if (!same_bytes(STRINGIFY_INNER(÷), "\xc3\xb7")) return 7;
  if (!same_bytes(STRINGIFY(÷), "\xc3\xb7")) return 8;
  /* Foreign C '/' and ordinary pointer syntax remain available. */
  if (value / 3 != 6 || value != 18) return 9;
  return 0;
}
