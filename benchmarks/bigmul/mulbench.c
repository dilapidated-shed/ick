/* mulbench.c: portable, in-process, unsigned 32-bit limb multiplication lab.
 * Inputs and output are little-endian arrays of limbs, independent of CPU endian.
 * Compile: cc -O3 -std=c11 -D_POSIX_C_SOURCE=200809L mulbench.c -o mulbench
 * Or:      cc -O3 -std=c11 -D_POSIX_C_SOURCE=200809L -DHAVE_CANDIDATE \
 *                 mulbench.c candidate.c -o mulbench-candidate
 * candidate.c must implement mul_candidate with the signature below.
 * The candidate MUST write all na+nb output limbs and preserve its inputs.
 * The measured interval includes a candidate's scratch allocation if it uses it.
 */
#include <stdint.h>
#include <stddef.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <ctype.h>

int mul_schoolbook(const uint32_t *a, size_t na,
                   const uint32_t *b, size_t nb, uint32_t *out) {
    /* This low-level ABI requires nonoverlapping, aligned arrays.
     * Check nulls and lengths before computing a byte count on 32-bit hosts. */
    if (!a || !b || !out || !na || !nb ||
        nb > SIZE_MAX / sizeof(*out) ||
        na > SIZE_MAX / sizeof(*out) - nb) return 1;
    memset(out, 0, (na + nb) * sizeof(*out));
    for (size_t i = 0; i < na; ++i) {
        uint64_t carry = 0;
        for (size_t j = 0; j < nb; ++j) {
            uint64_t x = (uint64_t)a[i] * b[j] + out[i+j] + carry;
            out[i+j] = (uint32_t)x;
            carry = x >> 32;
        }
        out[i + nb] = (uint32_t)carry;
    }
    return 0;
}

#ifdef HAVE_CANDIDATE
extern int mul_candidate(const uint32_t *, size_t,
                         const uint32_t *, size_t, uint32_t *);
#define MUL mul_candidate
#define NAME "candidate"
#else
#define MUL mul_schoolbook
#define NAME "schoolbook"
#endif

static size_t limbs(size_t bits) { return bits ? (bits - 1) / 32 + 1 : 1; }
static uint64_t rng_state = UINT64_C(0x4f63d97ac82157b1);
static uint64_t splitmix64(void) {
    uint64_t z = (rng_state += UINT64_C(0x9e3779b97f4a7c15));
    z = (z ^ (z >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94d049bb133111eb);
    return z ^ (z >> 31);
}
static void setbit(uint32_t *a, size_t k) { a[k / 32] |= UINT32_C(1) << (k % 32); }
static void fill(uint32_t *a, size_t bits, int kind) {
    size_t n = limbs(bits);
    memset(a, 0, n * sizeof(*a));
    if (bits == 0) return;
    for (size_t i = 0; i < n; ++i) {
        switch (kind) {
        case 0: a[i] = (uint32_t)splitmix64(); break; /* dense random */
        case 1: a[i] = UINT32_MAX; break; /* carry avalanche */
        case 2: a[i] = (i % 2) ? UINT32_C(0xaaaaaaaa) : UINT32_C(0x55555555); break;
        case 3: break; /* sparse */
        case 4: break; /* a single top bit */
        default: break;
        }
    }
    unsigned rem = (unsigned)(bits % 32);
    if (rem) a[n-1] &= (UINT32_C(1) << rem) - 1;
    if (kind == 3) { setbit(a, 0); setbit(a, bits/2); }
    setbit(a, bits - 1); /* ensure stated size, including sparse and checkerboard */
}

static uint64_t clock_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) { perror("clock_gettime"); exit(2); }
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + (uint64_t)ts.tv_nsec;
}
static int cmp_d(const void *a, const void *b) {
    const double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static volatile uint32_t sink;
static void benchmark_one(size_t abits, size_t bbits, int kind, int samples) {
    size_t na = limbs(abits), nb = limbs(bbits);
    if (nb > SIZE_MAX / sizeof(uint32_t) ||
        na > SIZE_MAX / sizeof(uint32_t) - nb) exit(3);
    uint32_t *a = malloc(na * sizeof(*a));
    uint32_t *b = malloc(nb * sizeof(*b));
    uint32_t *out = malloc((na+nb) * sizeof(*out));
    if (!a || !b || !out) { fprintf(stderr, "allocation failed\n"); exit(3); }
    fill(a, abits, kind);
    fill(b, bbits, (kind == 2) ? 1 : kind);
    if (MUL(a, na, b, nb, out)) { fprintf(stderr, "multiplication failed\n"); exit(4); }

    /* Calibrate one timing batch to about 15ms, at least one call. */
    size_t reps = 1;
    for (;;) {
        uint64_t t0 = clock_ns();
        for (size_t j=0; j<reps; ++j) {
            if (MUL(a, na, b, nb, out)) exit(4);
            sink ^= out[(j + na/2) % (na+nb)];
        }
        uint64_t elapsed = clock_ns() - t0;
        if (elapsed >= UINT64_C(15000000) || reps >= 16384) break;
        reps *= 2;
    }
    double samples_ns[31];
    if (samples < 1 || samples > 31) exit(5);
    for (int k=0; k<samples; ++k) {
        uint64_t t0 = clock_ns();
        for (size_t j=0; j<reps; ++j) {
            if (MUL(a, na, b, nb, out)) exit(4);
            sink ^= out[(j+k) % (na+nb)];
        }
        samples_ns[k] = (double)(clock_ns() - t0) / (double)reps;
    }
    qsort(samples_ns, (size_t)samples, sizeof(*samples_ns), cmp_d);
    printf("%s,%d,%zu,%zu,%zu,%.2f,%.2f,%" PRIu32 "\n",
           NAME, kind, abits, bbits, reps, samples_ns[samples/2],
           samples_ns[(size_t)((samples-1)*9/10)], sink);
    free(a); free(b); free(out);
}

static int digitval(int c) {
    if (c >= '0' && c <= '9') return c-'0';
    if (c >= 'a' && c <= 'f') return c-'a'+10;
    if (c >= 'A' && c <= 'F') return c-'A'+10;
    return -1;
}
static int from_hex(const char *s, uint32_t **words, size_t *count, int *neg) {
    *neg = (*s == '-');
    if (*neg || *s == '+') ++s;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    size_t len = strlen(s);
    if (!len || len > SIZE_MAX-7) return 1;
    size_t n = (len+7)/8;
    if (n > SIZE_MAX/sizeof(uint32_t)) return 1;
    uint32_t *a = calloc(n, sizeof(*a));
    if (!a) return 1;
    for (size_t i = 0; i < len; ++i) {
        int d = digitval((unsigned char)s[len-1-i]);
        if (d < 0) { free(a); return 1; }
        a[i/8] |= (uint32_t)d << ((i%8)*4);
    }
    while (n > 1 && !a[n-1]) --n;
    *count = n;
    *words = a;
    return 0;
}
static void print_hex(const uint32_t *a, size_t n, int negative) {
    while (n > 1 && !a[n-1]) --n;
    if (negative && (n != 1 || a[0])) putchar('-');
    printf("%x", a[n-1]);
    for (size_t i=n-1; i>0; --i) printf("%08x", a[i-1]);
    putchar('\n');
}
/* Bounded source protocol; this limit is in input bytes, not operand bits. */
#define MAX_RECORD_CHARS ((size_t)1048576)

static int read_record(char *line, size_t *length) {
    size_t len = 0;
    int ch;
    while ((ch = fgetc(stdin)) != EOF && ch != '\n') {
        if (ch == 0) return -1;
        if (len == MAX_RECORD_CHARS) return -2;
        line[len++] = (char)ch;
    }
    if (ferror(stdin)) return -3;
    if (ch == EOF && len == 0) return 0;
    line[len] = '\0';
    *length = len;
    return 1;
}

/* Correctness-only adapter; timed --bench still measures raw MUL. It detects
 * output under/overwrite by one word, input mutation and omitted output
 * stores using different prefills. Arbitrary overflow still needs ASan. */
static int checked_protocol_product(const uint32_t *a, size_t na,
                                    const uint32_t *b, size_t nb,
                                    uint32_t *out) {
    if (!a || !b || !out || !na || !nb ||
        nb > SIZE_MAX / sizeof(*out) - 2 ||
        na > SIZE_MAX / sizeof(*out) - 2 - nb) return 1;
    size_t count = na + nb;
    if (na > SIZE_MAX / sizeof(*a) || nb > SIZE_MAX / sizeof(*b))
        return 1;
    size_t abytes = na * sizeof(*a), bbytes = nb * sizeof(*b);
    size_t obytes = count * sizeof(*out);
    uint32_t *saved_a = malloc(abytes), *saved_b = malloc(bbytes);
    uint32_t *guarded = malloc((count + 2) * sizeof(*guarded));
    uint32_t *first = malloc(obytes);
    if (!saved_a || !saved_b || !guarded || !first) {
        free(saved_a); free(saved_b); free(guarded); free(first);
        return 1;
    }
    memcpy(saved_a, a, abytes);
    memcpy(saved_b, b, bbytes);
    int failure = 0;
    for (int pass = 0; pass < 2; ++pass) {
        guarded[0] = UINT32_C(0xc0deface);
        guarded[count + 1] = UINT32_C(0x5afe0123);
        memset(guarded + 1, pass ? 0x5a : 0xa5, obytes);
        if (MUL(a, na, b, nb, guarded + 1) != 0 ||
            guarded[0] != UINT32_C(0xc0deface) ||
            guarded[count + 1] != UINT32_C(0x5afe0123) ||
            memcmp(a, saved_a, abytes) ||
            memcmp(b, saved_b, bbytes)) {
            failure = 1;
            break;
        }
        if (pass == 0) memcpy(first, guarded + 1, obytes);
        else if (memcmp(first, guarded + 1, obytes)) failure = 1;
    }
    if (!failure) memcpy(out, first, obytes);
    free(saved_a); free(saved_b); free(guarded); free(first);
    return failure;
}

static int protocol(void) {
    char *line = malloc(MAX_RECORD_CHARS + 1);
    if (!line) { fprintf(stderr, "protocol record allocation failed\n"); return 3; }
    for (;;) {
        size_t len = 0;
        int record = read_record(line, &len);
        if (record == 0) break;
        if (record < 0) {
            fprintf(stderr, "malformed, binary, or overlong protocol record\n");
            free(line);
            return 2;
        }
        if (!len) continue;
        char *a_s = line;
        while (isspace((unsigned char)*a_s)) ++a_s;
        if (!*a_s) continue;
        char *b_s = a_s;
        while (*b_s && !isspace((unsigned char)*b_s)) ++b_s;
        if (!*b_s) {
            fprintf(stderr, "expected exactly two hex operands\n");
            free(line);
            return 2;
        }
        *b_s++ = '\0';
        while (isspace((unsigned char)*b_s)) ++b_s;
        char *end = b_s;
        while (*end && !isspace((unsigned char)*end)) ++end;
        char *tail = end;
        while (isspace((unsigned char)*tail)) ++tail;
        if (*tail) {
            fprintf(stderr, "extra protocol operand or trailing data\n");
            free(line);
            return 2;
        }
        *end = '\0';
        uint32_t *a = NULL, *b = NULL, *out = NULL;
        size_t na = 0, nb = 0;
        int aneg = 0, bneg = 0;
        if (from_hex(a_s, &a, &na, &aneg) ||
            from_hex(b_s, &b, &nb, &bneg)) {
            fprintf(stderr, "bad hex operand\n");
            free(a); free(b); free(line);
            return 2;
        }
        if (na > SIZE_MAX - nb ||
            nb > SIZE_MAX / sizeof(*out) ||
            na > SIZE_MAX / sizeof(*out) - nb) {
            fprintf(stderr, "size overflow\n");
            free(a); free(b); free(line);
            return 2;
        }
        out = malloc((na + nb) * sizeof(*out));
        if (!out) { free(a); free(b); free(line); return 3; }
        memset(out, 0xa5, (na + nb) * sizeof(*out));
        if (checked_protocol_product(a, na, b, nb, out)) {
            fprintf(stderr, "candidate violated the checked C ABI\n");
            free(a); free(b); free(out); free(line);
            return 4;
        }
        print_hex(out, na + nb, aneg ^ bneg);
        fflush(stdout);
        free(a); free(b); free(out);
    }
    free(line);
    return ferror(stdin) ? 2 : 0;
}

/* Refuse prefix parses and size_t overflows on both 32- and 64-bit hosts. */
static int decimal_size(const char *text, size_t *value) {
    if (!*text) return 1;
    size_t result = 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; ++p) {
        if (*p < '0' || *p > '9') return 1;
        unsigned digit = (unsigned)(*p - '0');
        if (result > (SIZE_MAX - digit) / 10) return 1;
        result = result * 10 + digit;
    }
    if (!result) return 1;
    *value = result;
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 2 && !strcmp(argv[1], "--pipe")) {
        if (argc != 2) return 2;
        return protocol();
    }
    if (argc >= 2 && !strcmp(argv[1], "--bench")) {
        if (argc > 4) return 2;
        size_t maxbits = 8192, sample_count = 7;
        if ((argc > 2 && decimal_size(argv[2], &maxbits)) ||
            (argc > 3 && decimal_size(argv[3], &sample_count)) ||
            maxbits > 1048576 || sample_count > 31) return 2;
        int samples = (int)sample_count;
        static const size_t sizes[] = {
            31,32,33,63,64,65,127,128,129,255,256,257,
            511,512,513,1023,1024,1025,2047,2048,2049,4096,8192,
            16384,32768,65536,131072,262144,524288,1048576
        };
        if (!maxbits || samples < 1 || samples > 31) return 2;
        puts("implementation,pattern,bits_a,bits_b,reps,median_ns,p90_ns,sink");
        for (size_t i=0; i<sizeof(sizes)/sizeof(*sizes); ++i) {
            size_t n = sizes[i];
            if (n > maxbits) break;
            for (int k=0; k<5; ++k) benchmark_one(n, n, k, samples);
            if (n >= 256) benchmark_one(n, n / 16, 0, samples);
            fflush(stdout);
        }
        return 0;
    }
    fprintf(stderr, "usage: %s --pipe | --bench [max_bits=8192] [samples=7]\n", argv[0]);
    return 2;
}
