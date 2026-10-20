/* Example candidate interface ONLY; not the paper's algorithm.
 * Replace this file with the ICK experimental multiplier wrapper.
 * All lengths refer to 32-bit little-endian limbs and must be positive.
 */
#include <stdint.h>
#include <stddef.h>
extern int mul_schoolbook(const uint32_t *, size_t,
                          const uint32_t *, size_t, uint32_t *);
int mul_candidate(const uint32_t *a, size_t na,
                  const uint32_t *b, size_t nb, uint32_t *out) {
    return mul_schoolbook(a, na, b, nb, out);
}
