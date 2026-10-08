/* { dg-do run } */
/* { dg-options "-std=c11 -O2 -Wall -Wextra -Werror" } */
#define PRODUCT(left, right) ((left) × (right))
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
static unsigned next_value(unsigned *calls)
{
  ++*calls;
  return 3;
}
int main(void)
{
  unsigned calls ← 0;
  unsigned product ← PRODUCT(next_value(&calls), 7);
  if (calls != 1 || product != 21) return 1;
  if (2 + 3 × 4 != 14 || 24 / 3 × 2 != 16) return 2;
  if (0.5 × 8.0 != 4.0) return 3;
  int value ← 5;
  int *pointer ← &value;
  if (*pointer × 3 != 15) return 4;
  if (!same_bytes("×", "\xc3\x97")) return 5;
  if (!same_bytes(STRINGIFY_INNER(×), "\xc3\x97")) return 6;
  if (!same_bytes(STRINGIFY(×), "\xc3\x97")) return 7;
  /* Ordinary multiplication and pointer/member syntax remain available. */
  if (value * 3 != 15 || value == 0 || value != 5) return 8;
  return 0;
}
