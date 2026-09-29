/*
 * Compile-time object-layout reasoning without system headers.
 */
struct byte_pair {
    unsigned char first;
    unsigned char second;
};

struct mixed_pair {
    unsigned char tag;
    unsigned int value;
};

_Static_assert(sizeof(struct byte_pair) >= 2,
               "two byte members must occupy at least two bytes");
_Static_assert(sizeof(struct mixed_pair)
                   >= sizeof(unsigned char) + sizeof(unsigned int),
               "aggregate size must contain both members");

unsigned long
mixed_pair_size(void)
{
    return (unsigned long)sizeof(struct mixed_pair);
}
