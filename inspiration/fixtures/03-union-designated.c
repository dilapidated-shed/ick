/*
 * Tests union construction plus a designated initializer without relying on
 * type-punning semantics or target endianness.
 */
union word_view {
    unsigned int word;
    unsigned char bytes[sizeof(unsigned int)];
};

unsigned int
union_designated_round_trip(unsigned int value)
{
    union word_view view = { .word = value };
    return view.word;
}
