/* { dg-do run } */
/* { dg-options "-O2" } */

_Static_assert (sizeof (float _Complex) == 2 * sizeof (float),
		"float complex must occupy two scalar slots");
_Static_assert (sizeof (double _Complex) == 2 * sizeof (double),
		"double complex must occupy two scalar slots");

static double _Complex static_z = 3.0 + 4.0i;
static double _Complex static_negative_axis = -2.0 + 0.0i;
static double _Complex static_zero = 0.0 + 0.0i;
static float _Complex static_float_negative_axis = -2.0f + 0.0fi;

/* Keep byte inspection across an optimization boundary so it observes the
   physical representation after complex lowering.  */
__attribute__ ((noinline, noipa))
static void
copy_bytes (void *destination, const void *source, unsigned long size)
{
  unsigned char *to = (unsigned char *) destination;
  const unsigned char *from = (const unsigned char *) source;

  for (unsigned long index = 0; index < size; ++index)
    to[index] = from[index];
}

static int
close_enough (double actual, double expected)
{
  double difference = actual - expected;
  return difference < 1e-12 && difference > -1e-12;
}

static int
close_enough_float (float actual, float expected)
{
  float difference = actual - expected;
  return difference < 2e-6f && difference > -2e-6f;
}

/* Exercise both directions of constant folding through complete object
   bytes.  The bytes are physical polar storage, while component access is
   semantic Cartesian access.  */
__attribute__ ((noinline, noipa))
static int
fold_semantic_constant_to_object_bytes (void)
{
  double _Complex value = 3.0 + 4.0i;
  double slots[2];
  __builtin_memcpy (slots, &value, sizeof slots);
  return (close_enough (slots[0], 5.0)
	  && close_enough (slots[1], __builtin_atan2 (4.0, 3.0)));
}

__attribute__ ((noinline, noipa))
static int
fold_object_bytes_to_semantic_constant (void)
{
  double slots[2] = { 5.0, 0x1.dac670561bb4fp-1 };
  double _Complex value;
  __builtin_memcpy (&value, slots, sizeof value);
  return (close_enough (__real__ value, 3.0)
	  && close_enough (__imag__ value, 4.0));
}

__attribute__ ((noinline, noipa))
static double _Complex
bounce (double _Complex value)
{
  return value;
}

__attribute__ ((noinline, noipa))
static double _Complex
return_constant (void)
{
  return 3.0 + 4.0i;
}

__attribute__ ((noinline, noipa))
static void
set_real_component (double _Complex *value, double real)
{
  __real__ *value = real;
}

__attribute__ ((noinline, noipa))
static void
set_imaginary_component (double _Complex *value, double imaginary)
{
  __imag__ *value = imaginary;
}

__attribute__ ((noinline, noipa))
static void
set_cartesian_components (double _Complex *value, double real,
			  double imaginary)
{
  __real__ *value = real;
  __imag__ *value = imaginary;
}

int
main (void)
{
  double raw[2];
  copy_bytes (raw, &static_z, sizeof raw);
  if (!close_enough (raw[0], 5.0)
      || !close_enough (raw[1], __builtin_atan2 (4.0, 3.0)))
    return 1;

  /* Language-level Cartesian access is reconstructed from polar storage.  */
  if (!close_enough (__real__ static_z, 3.0)
      || !close_enough (__imag__ static_z, 4.0))
    return 2;

  double negative_raw[2];
  copy_bytes (negative_raw, &static_negative_axis, sizeof negative_raw);
  if (!close_enough (negative_raw[0], 2.0)
      || !close_enough (negative_raw[1],
			__builtin_atan2 (0.0, -2.0))
      || !close_enough (__real__ static_negative_axis, -2.0)
      || !close_enough (__imag__ static_negative_axis, 0.0))
    return 3;

  double zero_raw[2];
  copy_bytes (zero_raw, &static_zero, sizeof zero_raw);
  if (zero_raw[0] != 0.0 || zero_raw[1] != 0.0)
    return 4;

  /* Exercise runtime Cartesian-to-polar construction, not only constants.
     At -O2 the addressable assignment is lowered to adjacent component
     stores, which must be paired before either physical slot is written.  */
  volatile double runtime_real = 3.0;
  volatile double runtime_imag = 4.0;
  double _Complex automatic_z
    = __builtin_complex (runtime_real, runtime_imag);
  double automatic_raw[2];
  copy_bytes (automatic_raw, &automatic_z, sizeof automatic_raw);
  if (!close_enough (automatic_raw[0], 5.0)
      || !close_enough (automatic_raw[1], raw[1]))
    return 5;

  /* ICK-to-ICK function arguments and returns carry the same polar pair.  */
  double _Complex returned_z = bounce (automatic_z);
  double returned_raw[2];
  copy_bytes (returned_raw, &returned_z, sizeof returned_raw);
  if (returned_raw[0] != automatic_raw[0]
      || returned_raw[1] != automatic_raw[1])
    return 6;

  double _Complex constant_returned = bounce (3.0 + 4.0i);
  double constant_returned_raw[2];
  copy_bytes (constant_returned_raw, &constant_returned,
	      sizeof constant_returned_raw);
  if (!close_enough (constant_returned_raw[0], 5.0)
      || !close_enough (constant_returned_raw[1], raw[1]))
    return 7;

  /* Multiplication operates natively on the polar pair.  */
  double _Complex unit_diagonal = bounce (1.0 + 1.0i);
  double _Complex product = unit_diagonal * unit_diagonal;
  double product_raw[2];
  copy_bytes (product_raw, &product, sizeof product_raw);
  if (!close_enough (product_raw[0], 2.0)
      || !close_enough (__real__ product, 0.0)
      || !close_enough (__imag__ product, 2.0)
      || !close_enough (__builtin_cabs (product), 2.0)
      || !close_enough (__builtin_carg (product),
			__builtin_atan2 (2.0, 0.0)))
    return 8;

  /* A principal +pi phase must not flip to -pi through sinf(pi).  */
  float float_negative_raw[2];
  copy_bytes (float_negative_raw, &static_float_negative_axis,
	      sizeof float_negative_raw);
  if (!close_enough_float (float_negative_raw[0], 2.0f)
      || __builtin_cargf (static_float_negative_axis)
	 != float_negative_raw[1])
    return 9;

  /* Multiplication may move the stored phase outside the principal range;
     carg must normalize that result rather than returning the raw slot.  */
  double phase_two_raw[2] = { 1.0, 2.0 };
  double _Complex phase_two;
  copy_bytes (&phase_two, phase_two_raw, sizeof phase_two);
  double _Complex phase_four = phase_two * phase_two;
  double phase_four_raw[2];
  copy_bytes (phase_four_raw, &phase_four, sizeof phase_four_raw);
  if (phase_four_raw[0] != 1.0 || phase_four_raw[1] != 4.0
      || !close_enough (__builtin_carg (phase_four),
			__builtin_atan2 (__builtin_sin (4.0),
					 __builtin_cos (4.0))))
    return 10;

  /* Adjacent component stores are also how optimization can lower a complete
     Cartesian assignment to an addressable complex object.  */
  set_cartesian_components (&automatic_z, 5.0, 12.0);
  double paired_store_raw[2];
  copy_bytes (paired_store_raw, &automatic_z, sizeof paired_store_raw);
  if (!close_enough (paired_store_raw[0], 13.0)
      || !close_enough (paired_store_raw[1],
			__builtin_atan2 (12.0, 5.0)))
    return 11;

  /* A standalone component lvalue store is a Cartesian operation, not a raw
     radius or angle write.  Keep these stores in separate functions so each
     lowering must reconstruct the untouched Cartesian component.  */
  set_real_component (&automatic_z, 6.0);
  set_imaginary_component (&automatic_z, 8.0);
  double component_store_raw[2];
  copy_bytes (component_store_raw, &automatic_z,
	      sizeof component_store_raw);
  if (!close_enough (component_store_raw[0], 10.0)
      || !close_enough (component_store_raw[1],
			__builtin_atan2 (8.0, 6.0))
      || !close_enough (__real__ automatic_z, 6.0)
      || !close_enough (__imag__ automatic_z, 8.0))
    return 12;

  /* A literal can survive optimization directly on GIMPLE_RETURN, without a
     complex assignment that would otherwise polarize it.  */
  double _Complex direct_constant = return_constant ();
  double direct_constant_raw[2];
  copy_bytes (direct_constant_raw, &direct_constant,
	      sizeof direct_constant_raw);
  if (!close_enough (direct_constant_raw[0], 5.0)
      || !close_enough (direct_constant_raw[1], raw[1]))
    return 13;

  if (!fold_semantic_constant_to_object_bytes ())
    return 14;

  if (!fold_object_bytes_to_semantic_constant ())
    return 15;

  return 0;
}
