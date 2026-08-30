/* { dg-do compile } */
/* { dg-options "-O2 -fdump-tree-optimized" } */

static int
close_enough (double actual, double expected)
{
  double difference = actual - expected;
  return difference < 1e-12 && difference > -1e-12;
}

/* A semantic complex constant must encode as the physical
   (modulus, argument) object representation.  */
__attribute__ ((noinline, noipa))
int
semantic_constant_to_object_bytes (void)
{
  double _Complex value = 3.0 + 4.0i;
  double slots[2];
  __builtin_memcpy (slots, &value, sizeof slots);
  return (slots[0] == 5.0
	  && slots[1] == 0x1.dac670561bb4fp-1);
}

/* A complete physical object image must decode before a language-level
   component access is folded.  */
__attribute__ ((noinline, noipa))
int
object_bytes_to_semantic_constant (void)
{
  double slots[2] = { 5.0, 0x1.dac670561bb4fp-1 };
  double _Complex value;
  __builtin_memcpy (&value, slots, sizeof value);
  return (close_enough (__real__ value, 3.0)
	  && close_enough (__imag__ value, 4.0));
}

/* { dg-final { scan-tree-dump-times "return 1;" 2 "optimized" } } */
