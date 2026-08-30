/* This translation unit is compiled only by ICK.  Its exported boundary is
   deliberately Cartesian scalars and an array, never _Complex.  */

__attribute__ ((visibility ("default")))
void
ick_complex_cartesian (float left_real, float left_imag,
		       float right_real, float right_imag,
		       float output_cartesian[static 4])
{
  float _Complex left = __builtin_complex (left_real, left_imag);
  float _Complex right = __builtin_complex (right_real, right_imag);
  float _Complex product = left * right;
  float _Complex quotient = left / right;

  output_cartesian[0] = __real__ product;
  output_cartesian[1] = __imag__ product;
  output_cartesian[2] = __real__ quotient;
  output_cartesian[3] = __imag__ quotient;
}
