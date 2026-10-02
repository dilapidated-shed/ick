void
ick_fft_radix2_f32x4 (float *restrict even_real,
                      float *restrict even_imag,
                      float *restrict odd_real,
                      float *restrict odd_imag,
                      const float *restrict left_real,
                      const float *restrict left_imag,
                      const float *restrict right_real,
                      const float *restrict right_imag,
                      const float *restrict twiddle_real,
                      const float *restrict twiddle_imag,
                      unsigned count);

static int
same4 (const float actual[4], const float expected[4])
{
  unsigned i;
  for (i = 0; i < 4; ++i)
    if (actual[i] != expected[i])
      return 0;
  return 1;
}

int
main (void)
{
  const float left_real[4] = { 10, 20, 30, 40 };
  const float left_imag[4] = { 1, 2, 3, 4 };
  const float right_real[4] = { 1, 2, 3, 4 };
  const float right_imag[4] = { 5, 6, 7, 8 };
  const float twiddle_real[4] = { 1, 0, -1, 0 };
  const float twiddle_imag[4] = { 0, 1, 0, -1 };
  const float expected_even_real[4] = { 11, 14, 27, 48 };
  const float expected_even_imag[4] = { 6, 4, -4, 0 };
  const float expected_odd_real[4] = { 9, 26, 33, 32 };
  const float expected_odd_imag[4] = { -4, 0, 10, 8 };
  float even_real[4], even_imag[4], odd_real[4], odd_imag[4];

  ick_fft_radix2_f32x4 (even_real, even_imag, odd_real, odd_imag,
                        left_real, left_imag, right_real, right_imag,
                        twiddle_real, twiddle_imag, 4);

  if (!same4 (even_real, expected_even_real))
    return 1;
  if (!same4 (even_imag, expected_even_imag))
    return 2;
  if (!same4 (odd_real, expected_odd_real))
    return 3;
  if (!same4 (odd_imag, expected_odd_imag))
    return 4;
  return 0;
}
