/* ARMv7/NEON qualification kernel for the Fourier Voice path.
   The external boundary remains ordinary float pointers.  The four-lane
   vector type is internal to this translation unit so no compiler-specific
   vector ABI crosses the Android NDK boundary.  */

typedef float ick_f32x4 __attribute__ ((vector_size (16)));

static inline ick_f32x4
ick_load_f32x4 (const float *source)
{
  ick_f32x4 value;
  __builtin_memcpy (&value, source, sizeof value);
  return value;
}

static inline void
ick_store_f32x4 (float *destination, ick_f32x4 value)
{
  __builtin_memcpy (destination, &value, sizeof value);
}

__attribute__ ((visibility ("default")))
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
                      unsigned count)
{
  unsigned i;

  for (i = 0; i + 4 <= count; i += 4)
    {
      ick_f32x4 lr = ick_load_f32x4 (left_real + i);
      ick_f32x4 li = ick_load_f32x4 (left_imag + i);
      ick_f32x4 rr = ick_load_f32x4 (right_real + i);
      ick_f32x4 ri = ick_load_f32x4 (right_imag + i);
      ick_f32x4 wr = ick_load_f32x4 (twiddle_real + i);
      ick_f32x4 wi = ick_load_f32x4 (twiddle_imag + i);
      ick_f32x4 product_real = rr * wr - ri * wi;
      ick_f32x4 product_imag = rr * wi + ri * wr;

      ick_store_f32x4 (even_real + i, lr + product_real);
      ick_store_f32x4 (even_imag + i, li + product_imag);
      ick_store_f32x4 (odd_real + i, lr - product_real);
      ick_store_f32x4 (odd_imag + i, li - product_imag);
    }
}
