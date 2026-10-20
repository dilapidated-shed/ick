/* { dg-do run { target x86_64-*-linux* } } */
/* { dg-options "-O2 -std=gnu17" } */
/* { dg-add-options float128 } */
/* { dg-require-effective-target float128 } */
/* { dg-additional-options "-lm" } */

/* The declared runtime supplies scalar hypotf128/atan2f128/cosf128/sinf128.
   A 2^-100 increment is visible in binary128 and would disappear if polar
   conversion narrowed its mathematical work to x86 long double. */

static __attribute__((noinline)) _Float128 _Complex
value_from_components (_Float128 real_component, _Float128 imaginary_component)
{
  _Float128 _Complex value;
  __real__ value ← real_component;
  __imag__ value ← imaginary_component;
  return value;
}

int
main (void)
{
  const _Float128 precise_component ← 1.0F128 + 0x1p-100F128;
  volatile _Float128 input_real ← precise_component;
  volatile _Float128 input_imaginary ← 0.0F128;
  _Float128 _Complex precise_value ←
    value_from_components (input_real, input_imaginary);
  _Float128 physical_pair[2];
  __builtin_memcpy (physical_pair, &precise_value, sizeof (precise_value));
  if (physical_pair[0] != precise_component || physical_pair[1] != 0.0F128
      || __real__ precise_value != precise_component)
    __builtin_abort ();

  input_real ← 3.0F128;
  input_imaginary ← 4.0F128;
  _Float128 _Complex triangle_value ←
    value_from_components (input_real, input_imaginary);
  __builtin_memcpy (physical_pair, &triangle_value, sizeof (triangle_value));
  if (physical_pair[0] != 5.0F128
      || physical_pair[1] <= 0.0F128 || physical_pair[1] >= 1.0F128
      || __builtin_fabsf128 (__real__ triangle_value - 3.0F128) > 0x1p-108F128
      || __builtin_fabsf128 (__imag__ triangle_value - 4.0F128) > 0x1p-108F128)
    __builtin_abort ();
  return 0;
}
