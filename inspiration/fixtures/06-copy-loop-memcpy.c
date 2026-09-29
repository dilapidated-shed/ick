/*
 * Reduction for three real source shapes:
 *   kernel generic memcpy implementation: explicit byte loop
 *   Wegert: ordinary runtime-size memcpy call
 *   Pauli/ICK: fixed-size __builtin_memcpy object copy
 */
extern void *memcpy(void *destination, const void *source, unsigned long size);

void
copy_bytes_loop(unsigned char *destination,
                const unsigned char *source,
                unsigned long count)
{
    while (count != 0) {
        *destination++ = *source++;
        --count;
    }
}

void
copy_runtime_memcpy(void *destination,
                    const void *source,
                    unsigned long count)
{
    memcpy(destination, source, count);
}

#ifdef TEST_BUILTIN_MEMCPY
void
copy_fixed_builtin(void *destination, const void *source)
{
    __builtin_memcpy(destination, source, 16u);
}
#endif
