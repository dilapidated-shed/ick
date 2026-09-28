/* The library acts by Hamilton products; this oracle acts by a rotation matrix.
 * Compile without contraction or fast-math. No binary64 working arithmetic.
 */
void geometry_oracle_rotate(const float quaternion[4], const float point[3], float output[3])
{
    const float w = quaternion[0], x = quaternion[1];
    const float y = quaternion[2], z = quaternion[3];
    const float matrix[3][3] = {
        {1.0f - 2.0f*(y*y + z*z), 2.0f*(x*y - w*z), 2.0f*(x*z + w*y)},
        {2.0f*(x*y + w*z), 1.0f - 2.0f*(x*x + z*z), 2.0f*(y*z - w*x)},
        {2.0f*(x*z - w*y), 2.0f*(y*z + w*x), 1.0f - 2.0f*(x*x + y*y)}
    };
    for (unsigned row = 0; row < 3; ++row) {
        output[row] = 0.0f;
        for (unsigned column = 0; column < 3; ++column)
            output[row] += matrix[row][column] * point[column];
    }
}
