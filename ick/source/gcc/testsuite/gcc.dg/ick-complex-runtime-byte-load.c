/* { dg-do run } */
/* { dg-options "-O2 -fno-strict-aliasing" } */
/* { dg-additional-options "-lm" } */

/* A byte copy and an explicitly alias-enabled pointer inspection observe
   physical radius/angle slots.  They must not become Cartesian __real__ or
   __imag__ requests when address-taken objects enter SSA form.  */

static __attribute__((noinline)) double _Complex
double_value_from_components (double real_component, double imaginary_component)
{
  double _Complex value;
  __real__ value ← real_component;
  __imag__ value ← imaginary_component;
  return value;
}

static __attribute__((noinline)) float _Complex
float_value_from_components (float real_component, float imaginary_component)
{
  float _Complex value;
  __real__ value ← real_component;
  __imag__ value ← imaginary_component;
  return value;
}

static __attribute__((noinline)) int _Complex
integer_value_from_components (int real_component, int imaginary_component)
{
  int _Complex value;
  __real__ value ← real_component;
  __imag__ value ← imaginary_component;
  return value;
}

int
main (void)
{
  volatile double real_input ← 3.0;
  volatile double imaginary_input ← 4.0;
  double _Complex double_value ←
    double_value_from_components (real_input, imaginary_input);
  double double_slots[2];
  __builtin_memcpy (double_slots, &double_value, sizeof (double_value));
  if (double_slots[0] != 5.0 || double_slots[1] <= 0.0
      || double_slots[1] >= 1.0
      || __builtin_fabs (__real__ double_value - 3.0) > 1e-12
      || __builtin_fabs (__imag__ double_value - 4.0) > 1e-12)
    return 1;

  double _Complex inspected_value ←
    double_value_from_components (real_input, imaginary_input);
  const double *radius_and_angle ← (const double *) &inspected_value;
  if (radius_and_angle[0] != 5.0 || radius_and_angle[1] <= 0.0
      || radius_and_angle[1] >= 1.0)
    return 2;

  float _Complex float_value ←
    float_value_from_components ((float) real_input, (float) imaginary_input);
  float float_slots[2];
  __builtin_memcpy (float_slots, &float_value, sizeof (float_value));
  if (float_slots[0] != 5.0f || float_slots[1] <= 0.0f
      || float_slots[1] >= 1.0f
      || __builtin_fabsf (__real__ float_value - 3.0f) > 2e-6f
      || __builtin_fabsf (__imag__ float_value - 4.0f) > 2e-6f)
    return 3;

  /* Integer complex retains its ordinary Cartesian storage.  */
  int _Complex integer_value ← integer_value_from_components (3, 4);
  int integer_slots[2];
  __builtin_memcpy (integer_slots, &integer_value, sizeof (integer_value));
  if (integer_slots[0] != 3 || integer_slots[1] != 4
      || __real__ integer_value != 3 || __imag__ integer_value != 4)
    return 4;
  return 0;
}
