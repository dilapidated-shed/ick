/* { dg-do run } */
/* { dg-options "-O0" } */

/* Component reads are semantic Cartesian values even when a function has no
   complex arithmetic.  Physical storage remains radius/angle.  In particular,
   creal/cimag builtins must enter complex lowering without another operation
   in the same function.  Run this file at O0/O1/O2/O3/Os in the native gate.  */

struct values
{
  float _Complex single[2];
  double _Complex wide[2];
};

__attribute__ ((noinline, noipa))
static void
initialize (struct values *values)
{
  values->single[0] = -1.0f + 0.6fi;
  values->single[1] = 1.0f - 0.4fi;
  values->wide[0] = 3.0 + 4.0i;
  values->wide[1] = -4.0 - 3.0i;
}

__attribute__ ((noinline, noipa))
static void
extract_member (const struct values *values, unsigned index, float *out)
{
  out[0] = __builtin_crealf (values->single[index]);
  out[1] = __builtin_cimagf (values->single[index]);
}

__attribute__ ((noinline, noipa))
static void
extract_value (float _Complex value, float *out)
{
  out[0] = __builtin_crealf (value);
  out[1] = __builtin_cimagf (value);
}

__attribute__ ((noinline, noipa))
static void
extract_wide (const double _Complex *value, double *out)
{
  out[0] = __builtin_creal (*value);
  out[1] = __builtin_cimag (*value);
}

__attribute__ ((noinline, noipa))
static void
extract_wide_value (double _Complex value, double *out)
{
  out[0] = __builtin_creal (value);
  out[1] = __builtin_cimag (value);
}

/* Keep ordinary language component syntax covered alongside the builtins.  */
__attribute__ ((noinline, noipa))
static void
extract_language (const struct values *values, unsigned index, float *out)
{
  out[0] = __real__ values->single[index];
  out[1] = __imag__ values->single[index];
}

static inline __attribute__ ((always_inline)) float
inline_real (float _Complex value)
{
  return __builtin_crealf (value);
}

static inline __attribute__ ((always_inline)) float
inline_imaginary (float _Complex value)
{
  return __builtin_cimagf (value);
}

__attribute__ ((noinline, noipa))
static void
extract_inline (const struct values *values, unsigned index, float *out)
{
  out[0] = inline_real (values->single[index]);
  out[1] = inline_imaginary (values->single[index]);
}

__attribute__ ((noinline, noipa))
static void
copy_storage (const void *source, void *destination, unsigned long size)
{
  __builtin_memcpy (destination, source, size);
}

static int
close_enough (double actual, double expected, double tolerance)
{
  double difference = actual - expected;
  return difference < tolerance && difference > -tolerance;
}

static int
check_float (const char *name, const float *actual, const float *expected)
{
  if (close_enough (actual[0], expected[0], 2e-6)
      && close_enough (actual[1], expected[1], 2e-6))
    return 0;
  __builtin_printf ("FAIL %s: %.9g %.9g expected %.9g %.9g\n", name,
                    (double) actual[0], (double) actual[1],
                    (double) expected[0], (double) expected[1]);
  return 1;
}

int
main (void)
{
  struct values values;
  const float expected[2][2] = { { -1.0f, 0.6f }, { 1.0f, -0.4f } };
  const double wide_expected[2][2] = { { 3.0, 4.0 }, { -4.0, -3.0 } };
  int failures = 0;
  initialize (&values);
  for (unsigned index = 0; index != 2; ++index)
    {
      float out[2];
      double wide[2];
      extract_member (&values, index, out);
      failures += check_float ("member", out, expected[index]);
      extract_value (values.single[index], out);
      failures += check_float ("value", out, expected[index]);
      extract_language (&values, index, out);
      failures += check_float ("language", out, expected[index]);
      extract_inline (&values, index, out);
      failures += check_float ("inline", out, expected[index]);
      extract_wide (&values.wide[index], wide);
      if (!close_enough (wide[0], wide_expected[index][0], 1e-12)
          || !close_enough (wide[1], wide_expected[index][1], 1e-12))
        ++failures;
      extract_wide_value (values.wide[index], wide);
      if (!close_enough (wide[0], wide_expected[index][0], 1e-12)
          || !close_enough (wide[1], wide_expected[index][1], 1e-12))
        ++failures;
    }

  double raw[2];
  copy_storage (&values.wide[0], raw, sizeof raw);
  if (!close_enough (raw[0], 5.0, 1e-12)
      || !close_enough (raw[1], __builtin_atan2 (4.0, 3.0), 1e-12))
    ++failures;
  return failures;
}
