/*
 * Two semantically similar copy paths: an explicit pointer/length loop and a
 * libc-style memcpy call. Define TEST_BUILTIN_MEMCPY to expose the compiler's
 * __builtin_memcpy path where supported.
 */
extern void *memcpy(void *destination, const void *source, unsigned long size);

void
copy_words_loop(unsigned int *destination,
                const unsigned int *source,
                unsigned int count)
{
    while (count != 0) {
        *destination++ = *source++;
        --count;
    }
}

void
copy_words_memcpy(unsigned int *destination,
                  const unsigned int *source,
                  unsigned int count)
{
    memcpy(destination, source,
           (unsigned long)count * (unsigned long)sizeof(unsigned int));
}

#ifdef TEST_BUILTIN_MEMCPY
void
copy_words_builtin(unsigned int *destination,
                   const unsigned int *source,
                   unsigned int count)
{
    __builtin_memcpy(destination, source,
                     (unsigned long)count * (unsigned long)sizeof(unsigned int));
}
#endif
