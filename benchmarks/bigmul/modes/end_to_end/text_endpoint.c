#include "../../providers/providers.h"
#include "../../timing/engine.h"
#include <gmp.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef MB_TEXT_TRACKED
#include "../../memory/tracker.h"
#endif
#ifdef MB_TEXT_PHASE_UNIT
#define MB_ENDPOINT_PHASES
#endif

extern int mul_schoolbook(const uint32_t *,size_t,const uint32_t *,size_t,uint32_t *);
enum { MAX_DIGITS=10*MB05_MAX_LIMBS+1, LINE_CAP=2*MAX_DIGITS+64 };
struct phases { uint64_t point[9]; };
static int stamp(struct phases *phases,size_t index) {
#ifdef MB_ENDPOINT_PHASES
    return mb_monotonic(NULL,&phases->point[index]);
#else
    (void)phases; (void)index; return 0;
#endif
}
static int read_line(char *line) {
    size_t used=0;
    for (;;) {
        int byte=getchar();
        if (byte==EOF) return ferror(stdin) || used ? 2 : 1;
        if (!byte || used+1>=LINE_CAP) return 2;
        if (byte=='\n') { line[used]=0; return 0; }
        line[used++]=(char)byte;
    }
}
static int length_field(char **cursor,size_t *length) {
    char *begin=*cursor,*end;
    if (*begin<'0' || *begin>'9') return 2;
    errno=0; uintmax_t value=strtoumax(begin,&end,10);
    if (errno || !value || value>MB05_MAX_LIMBS || *end!=' ') return 2;
    *length=(size_t)value; *cursor=end+1; return 0;
}
static int operand_field(char **cursor,char **text,int base,int last) {
    char *begin=*cursor,*end=begin; size_t digits=0;
    while (*end && *end!=' ') {
        int valid=(*end>='0' && *end<='9') || (base==16 && *end>='a' && *end<='f');
        if (!valid || ++digits>MAX_DIGITS) return 2;
        ++end;
    }
    if (!digits || (last ? *end!=0 : *end!=' ')) return 2;
    *text=begin;
    if (*end) { *end=0; *cursor=end+1; }
    else *cursor=end;
    return 0;
}
static int request(char *line,size_t request_index,int base,int echo,int kara,struct phases *phases) {
    size_t na,nb; char *cursor=line,*left_text,*right_text;
    if (length_field(&cursor,&na) || length_field(&cursor,&nb) ||
        operand_field(&cursor,&left_text,base,0) || operand_field(&cursor,&right_text,base,1)) return 2;
    if (stamp(phases,2)) return 3;
    mpz_t left,right,product;
    mpz_init(left); mpz_init(right); mpz_init(product);
    uint32_t *a=calloc(na,4),*b=calloc(nb,4),*out=calloc(na+nb,4);
    size_t width=(base==16 ? 8 : 10)*(na+nb);
    char *digits=calloc(width+2,1),*formatted=calloc(width+2,1);
    int status=0;
    if (!a || !b || !out || !digits || !formatted) { status=2; goto cleanup; }
    if (stamp(phases,3)) { status=3; goto cleanup; }
    if (mpz_set_str(left,left_text,base) || mpz_set_str(right,right_text,base) ||
        mpz_sizeinbase(left,2)>32*na || mpz_sizeinbase(right,2)>32*nb) { status=2; goto cleanup; }
    size_t count=0;
    (void)mpz_export(a,&count,-1,4,0,0,left);
    if (count>na) { status=2; goto cleanup; }
    (void)mpz_export(b,&count,-1,4,0,0,right);
    if (count>nb) { status=2; goto cleanup; }
    if (stamp(phases,4)) { status=3; goto cleanup; }
    if (!echo) status=kara ? mb05_karatsuba32(a,na,b,nb,out) : mul_schoolbook(a,na,b,nb,out);
    if (status) goto cleanup;
    if (stamp(phases,5)) { status=3; goto cleanup; }
#ifdef MB_TEXT_WRONG_PRODUCT
    out[na+nb-1]^=1;
#endif
    mpz_import(product,na+nb,-1,4,0,0,out);
    if (!mpz_get_str(digits,base,product)) { status=2; goto cleanup; }
    size_t length=strlen(digits);
    if (length>width) { status=2; goto cleanup; }
    memset(formatted,'0',width-length); memcpy(formatted+width-length,digits,length);
    formatted[width]='\n';
    if (stamp(phases,6)) { status=3; goto cleanup; }
    size_t output_count=width+1;
#ifdef MB_TEXT_TRUNCATE
    output_count-=2;
#endif
    if (fwrite(formatted,1,output_count,stdout)!=output_count || fflush(stdout)) status=2;
#ifdef MB_TEXT_SURPLUS
    if (putchar('0')==EOF || putchar('\n')==EOF || fflush(stdout)) status=2;
#endif
    if (stamp(phases,7)) status=3;
cleanup:
#ifdef MB_TEXT_ERROR_LEAK
    if (!status) free(a);
#else
    free(a);
#endif
    free(b); free(out); free(digits); free(formatted);
    mpz_clear(left); mpz_clear(right); mpz_clear(product);
    if (status) return status;
    if (stamp(phases,8)) return 3;
#ifdef MB_ENDPOINT_PHASES
    static const char *names[]={"read","parse","allocation","import","arithmetic","export-format","write-flush","cleanup"};
    const char *unit="ns";
#ifdef MB_TEXT_PHASE_UNIT
    unit="us";
#endif
    for (size_t phase=0;phase<8;++phase) {
        if (phases->point[phase+1]<phases->point[phase]) return 3;
        fprintf(stderr,"phase\t%zu\t%s\t%" PRIu64 "\t%s\n",request_index,names[phase],phases->point[phase+1]-phases->point[phase],unit);
    }
    fprintf(stderr,"provider_calls\t%zu\t%d\n",request_index,!echo);
#else
    (void)request_index;
#endif
#ifdef MB_EXIT_AFTER_OUTPUT
    return 99;
#endif
    return 0;
}
static int finish(char *line,int status) {
    free(line);
#ifdef MB_TEXT_TRACKED
    fprintf(stderr,"tracked_live_bytes\t%zu\n",mb_live());
    if (mb_live()) { fputs("tracked text endpoint leak\n",stderr); return 87; }
#endif
    return status;
}
int main(int argc,char **argv) {
    if (argc==2 && !strcmp(argv[1],"--metadata")) {
        printf("runtime_version\t%s\nheader_version\t%d.%d.%d\n",gmp_version,__GNU_MP_VERSION,__GNU_MP_VERSION_MINOR,__GNU_MP_VERSION_PATCHLEVEL);
        return 0;
    }
    if (argc!=3) return 2;
    int base=!strcmp(argv[1],"hex") ? 16 : !strcmp(argv[1],"decimal") ? 10 : 0;
    int echo=!strcmp(argv[2],"echo"),kara=!strcmp(argv[2],"karatsuba32-bounded");
    if (!base || (!echo && !kara && strcmp(argv[2],"schoolbook"))) return 2;
#ifdef MB_ENDPOINT_PHASES
    fputs("measurement\tphase-instrumented\n",stderr);
#else
    fputs("measurement\tuninstrumented\n",stderr);
#endif
    char *line=malloc(LINE_CAP);
    if (!line) return 2;
    int status=0;
    for (size_t request_index=0;request_index<1024;++request_index) {
        struct phases phases={{0}};
        if (stamp(&phases,0)) { status=3; break; }
        int received=read_line(line);
        if (received==1) return finish(line,0);
        if (received || stamp(&phases,1)) { status=2; break; }
        status=request(line,request_index,base,echo,kara,&phases);
        if (status) break;
        if (request_index==1023) {
            int extra=getchar();
            if (extra!=EOF || ferror(stdin)) status=2;
        }
    }
    return finish(line,status);
}
