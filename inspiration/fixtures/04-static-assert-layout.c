/*
 * Reduction for:
 *   Linux crypto/md5.c cross-structure size/offset contracts
 *   ICK exact storage/layout assertions
 */
struct state_a {
    unsigned int state[4];
    unsigned long count;
    unsigned char block[64];
};

struct state_b {
    unsigned int hash[4];
    unsigned long byte_count;
    unsigned char buffer[64];
};

_Static_assert(sizeof(struct state_a) == sizeof(struct state_b),
               "state objects must have identical total size");
_Static_assert(__builtin_offsetof(struct state_a, state)
                   == __builtin_offsetof(struct state_b, hash),
               "state/hash offsets must match");
_Static_assert(__builtin_offsetof(struct state_a, count)
                   == __builtin_offsetof(struct state_b, byte_count),
               "count offsets must match");
_Static_assert(__builtin_offsetof(struct state_a, block)
                   == __builtin_offsetof(struct state_b, buffer),
               "buffer offsets must match");

unsigned long
state_size(void)
{
    return (unsigned long)sizeof(struct state_a);
}
