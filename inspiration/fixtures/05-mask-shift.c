/*
 * Representative of compact numeric/geometry field extraction.
 */
unsigned int
extract_three_bits(unsigned int word)
{
    return (word >> 5) & 7u;
}

unsigned int
replace_three_bits(unsigned int word, unsigned int field)
{
    const unsigned int mask = 7u << 5;
    return (word & ~mask) | ((field & 7u) << 5);
}
