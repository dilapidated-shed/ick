#include "kernels.h"
void volume_kernel(float *output, float yaw_mix, float pitch_mix)
{
    (void)yaw_mix; (void)pitch_mix;
    for (unsigned index = 0; index < 3 * PIXELS; ++index) output[index] = 0.0f;
}
