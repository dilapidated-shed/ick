/* Independent expected C values; never derive them from ICKY Nat output. */
#define OCTAL 010
#define ASSIGN(target, value) __builtin_icky(target ← ( value ))
int main (void)
{
  int x = 0, y = 23;
  __builtin_icky(x ← 010);
  if (x != 8) return 1;
  __builtin_icky(x ← 10);
  if (x != 10) return 2;
  if (__builtin_icky(( ( y ) )) != 23) return 3;
  __builtin_icky(x /* π 🐈 */ ← /* exact raw comment */ OCTAL);
  if (x != 8) return 4;
  ASSIGN(x, 10);
  if (x != 10) return 5;
  __builtin_icky(x ← y);
  if (x != 23) return 6;
  /* Existing ICK syntax outside the selected lane remains ordinary C. */
  x ← 010;
  if (x != 8 || 6 × 3 != 18 || 8 ÷ 2 != 4) return 7;
  return 0;
}
