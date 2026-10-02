/* ARMv7/NEON qualification kernel for the Fourier Voice path.
   Keep the external boundary to ordinary float pointers.  The loop is
   deliberately ordinary C: the qualification requires ICK to turn four
   independent radix-2 complex butterflies into 128-bit NEON operations.  */

__attribute__ ((visibility ("default")))
void
ick_fft_radix2_f32 (float *restrict even_real,
                    float *restrict even_imag,
                    float *restrict odd_real,
                    float *restrict odd_imag,
                    const float *restrict left_real,
                    const float *restrict left_imag,
                    const float *restrict right_real,
                    const float *restrict right_imag,
                    const float *restrict twiddle_real,
                    const float *restrict twiddle_imag,
                    unsigned count)
{
  unsigned i;

  for (i = 0; i < count; ++i)
    {
      float product_real
        = right_real[i] * twiddle_real[i]
        - right_imag[i] * twiddle_imag[i];
      float product_imag
        = right_real[i] * twiddle_imag[i]
        + right_imag[i] * twiddle_real[i];

      even_real[i] = left_real[i] + product_real;
      even_imag[i] = left_imag[i] + product_imag;
      odd_real[i] = left_real[i] - product_real;
      odd_imag[i] = left_imag[i] - product_imag;
    }
}
