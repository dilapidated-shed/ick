#include "../../providers/providers.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
extern int mul_schoolbook(const uint32_t *, size_t, const uint32_t *, size_t, uint32_t *);
static void delay(void) { struct timespec duration={0,20000000}; while (nanosleep(&duration,&duration)) {} }
static int read_word(uint32_t *out, int allow_eof) {
    unsigned char b[4]; size_t got=fread(b,1,4,stdin);
    if (!got && feof(stdin) && allow_eof) return 1;
    if (got!=4) return 2;
    *out=(uint32_t)b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24); return 0;
}
static int write_word(uint32_t word) {
    unsigned char b[4]; for (unsigned i=0;i<4;++i) b[i]=(unsigned char)(word>>(8*i));
    return fwrite(b,1,4,stdout)!=4;
}
int main(int argc, char **argv) {
    if (argc!=2) return 2;
    int echo=!strcmp(argv[1],"echo"), kara=!strcmp(argv[1],"karatsuba32-bounded");
    if (!echo && !kara && strcmp(argv[1],"schoolbook")) return 2;
    (void)delay;
#ifdef MB_DELAY_START
    delay();
#endif
#ifdef MB_ENDPOINT_HANG
    for (;;) delay();
#endif
    for (size_t request=0;request<1024;++request) {
        uint32_t na,nb; int status=read_word(&na,1);
        if (status==1) return 0;
        if (status || read_word(&nb,0) || !na || !nb || na>MB05_MAX_LIMBS || nb>MB05_MAX_LIMBS) return 2;
        uint32_t *a=calloc(na,4), *b=calloc(nb,4), *out=calloc(na+nb,4);
        if (!a || !b || !out) { free(a); free(b); free(out); return 2; }
        for (size_t i=0;i<na;++i) if (read_word(&a[i],0)) status=2;
        for (size_t i=0;i<nb;++i) if (read_word(&b[i],0)) status=2;
        if (!status && !echo) status=kara ? mb05_karatsuba32(a,na,b,nb,out) : mul_schoolbook(a,na,b,nb,out);
#ifdef MB_ENDPOINT_CARRY
        out[na+nb-1]^=1;
#endif
#ifdef MB_DELAY_OUTPUT
        delay();
#endif
        if (!status) status=write_word(na+nb);
        size_t count=na+nb;
#ifdef MB_ENDPOINT_TRUNCATE
        --count;
#endif
        for (size_t i=0;i<count && !status;++i) status=write_word(out[i]);
        if (fflush(stdout)) status=2;
        free(a); free(b); free(out);
        if (status) return 2;
#ifdef MB_EXIT_AFTER_OUTPUT
        return 99;
#endif
    }
    return getchar()==EOF ? 0 : 2;
}
