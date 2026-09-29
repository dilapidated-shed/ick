/*
 * Independent reduction of the one-field wrapper pattern used by ICK's
 * imprecise and finite-geometry types.
 */
typedef struct {
    unsigned char payload;
} box8;

box8
box8_make(unsigned char payload)
{
    box8 value = { payload };
    return value;
}

unsigned char
box8_code(box8 value)
{
    return value.payload;
}
