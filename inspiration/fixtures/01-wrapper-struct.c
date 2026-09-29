/*
 * Reduction for:
 *   Linux atomic_t-style one-field aligned wrapper
 *   ICK E4M3/Circle96-style one-byte semantic wrapper
 *
 * The production sources, not this file, are authoritative.
 */
typedef struct {
    int counter __attribute__((aligned(sizeof(int))));
} aligned_counter;

typedef struct {
    unsigned char payload;
} byte_wrapper;

int
aligned_counter_value(aligned_counter value)
{
    return value.counter;
}

unsigned char
byte_wrapper_value(byte_wrapper value)
{
    return value.payload;
}
