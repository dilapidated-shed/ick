/* This translation unit is compiled by Android NDK Clang for the link gate
   and by a stock target compiler for an optional runtime gate.  It verifies
   the scalar/array ABI used at the ICK boundary.  */

extern void ick_complex_cartesian (float, float, float, float,
				   float[static 4]);

__attribute__ ((visibility ("default")))
int
wegert_ick_runtime_probe (void)
{
  float output[4];
  const float expected[4] = { 11.0f, -2.0f, -1.0f, 2.0f };

  ick_complex_cartesian (3.0f, 4.0f, 1.0f, -2.0f, output);

  for (unsigned int index = 0; index < 4; ++index)
    {
      float error = output[index] - expected[index];
      if (error < 0.0f)
	error = -error;
      /* The negated comparison also rejects infinities and NaNs.  */
      if (!(error <= 1.0e-4f))
	return (int) index + 1;
    }

  return 0;
}
