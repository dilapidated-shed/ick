#include "kernels.h"
/* Pauli-shaped, not a hydrogen accuracy or application parity fixture.
   All 458752 sample positions are evaluated (Pauli clips outside its sphere).
   Fixed rotation coefficients avoid libc and keep the benchmark self-contained.
   yaw_mix/pitch_mix vary between frames to prevent constant-frame elimination. */
void volume_kernel(float *output, float yaw_mix, float pitch_mix)
{
    for (unsigned y = 0; y < IMAGE_SIDE; ++y) {
        float v = ((float)y + 0.5f) * (1.0f / 64.0f) - 1.0f;
        for (unsigned x = 0; x < IMAGE_SIDE; ++x) {
            float u = ((float)x + 0.5f) * (1.0f / 64.0f) - 1.0f;
            float red = 0.0f, green = 0.0f, blue = 0.0f;
            for (unsigned sample = 0; sample < RAY_SAMPLES; ++sample) {
                float z = ((float)sample + 0.5f) * (1.0f / 16.0f) - 0.875f;
                float rotated_x = yaw_mix * u + 0.5f * z;
                float rotated_z = yaw_mix * z - 0.5f * u;
                float rotated_y = pitch_mix * v - 0.25f * rotated_z;
                float depth = pitch_mix * rotated_z + 0.25f * v;
                float radius_squared = rotated_x * rotated_x +
                    rotated_y * rotated_y + depth * depth;
                float polynomial = rotated_x * rotated_y * depth;
                float density = polynomial * polynomial / (1.0f + radius_squared);
                red += density * (1.0f + rotated_x * 0.25f);
                green += density * (1.0f + rotated_y * 0.25f);
                blue += density * (1.0f + depth * 0.25f);
            }
            output[3u * (y * IMAGE_SIDE + x)] = red;
            output[3u * (y * IMAGE_SIDE + x) + 1] = green;
            output[3u * (y * IMAGE_SIDE + x) + 2] = blue;
        }
    }
}
