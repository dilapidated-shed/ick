/* { dg-do run } */
/* { dg-options "-O2" } */

extern double floor (double);
extern double ceil (double);
extern float floorf (float);
extern float ceilf (float);

_Static_assert (sizeof (float _Complex) == 2 * sizeof (float),
		"float complex must occupy two scalar slots");
_Static_assert (sizeof (double _Complex) == 2 * sizeof (double),
		"double complex must occupy two scalar slots");

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
check_double (double radius, double angle,
	      double expected_floor, double expected_ceil)
{
  double source_raw[2] = { radius, angle };
  double _Complex source;
  copy_bytes (&source, source_raw, sizeof source);

  double _Complex down = floor (source);
  double _Complex up = ceil (source);
  double down_raw[2];
  double up_raw[2];
  copy_bytes (down_raw, &down, sizeof down_raw);
  copy_bytes (up_raw, &up, sizeof up_raw);

  if (down_raw[0] != expected_floor || up_raw[0] != expected_ceil)
    return 1;
  if (down_raw[1] != source_raw[1] || up_raw[1] != source_raw[1])
    return 2;
  return 0;
}

static int
check_float (float radius, float angle,
	     float expected_floor, float expected_ceil)
{
  float source_raw[2] = { radius, angle };
  float _Complex source;
  copy_bytes (&source, source_raw, sizeof source);

  float _Complex down = floorf (source);
  float _Complex up = ceilf (source);
  float down_raw[2];
  float up_raw[2];
  copy_bytes (down_raw, &down, sizeof down_raw);
  copy_bytes (up_raw, &up, sizeof up_raw);

  if (down_raw[0] != expected_floor || up_raw[0] != expected_ceil)
    return 1;
  if (down_raw[1] != source_raw[1] || up_raw[1] != source_raw[1])
    return 2;
  return 0;
}

int
main (void)
{
  int result;

  /* Zero radius may carry a latent phase, which both operations preserve.  */
  if ((result = check_double (0.0, -0.75, 0.0, 0.0)))
    return 10 + result;
  if ((result = check_float (0.0f, -0.75f, 0.0f, 0.0f)))
    return 20 + result;

  /* Floor may collapse the radius to zero without discarding its phase.  */
  if ((result = check_double (0.5, 0.25, 0.0, 1.0)))
    return 30 + result;
  if ((result = check_float (0.5f, 0.25f, 0.0f, 1.0f)))
    return 40 + result;

  if ((result = check_double (1.25, -1.0, 1.0, 2.0)))
    return 50 + result;
  if ((result = check_float (1.25f, -1.0f, 1.0f, 2.0f)))
    return 60 + result;

  /* Exact integer radii and axis phases remain bit-identical.  */
  if ((result = check_double (2.0, 0x1.921fb54442d18p+1,
			      2.0, 2.0)))
    return 70 + result;
  if ((result = check_float (2.0f, 0x1.921fb6p+1f, 2.0f, 2.0f)))
    return 80 + result;
  if ((result = check_double (5.0, __builtin_atan2 (4.0, 3.0),
			      5.0, 5.0)))
    return 90 + result;
  if ((result = check_float (5.0f,
			     __builtin_atan2f (4.0f, 3.0f),
			     5.0f, 5.0f)))
    return 100 + result;

  return 0;
}
