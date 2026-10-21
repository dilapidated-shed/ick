/* Uncompiled integration draft; NOT accepted candidate or paper execution.
 * Requires the actual accepted MUL5 API and an accepted record budget.
 * No short-product/whole-input fallback is provided here. */
#include <composition.h>
#include <stdint.h>
#include <string.h>
#ifndef MB16_RECORD_BUDGET
#error "An accepted MUL5 record budget must be explicitly supplied"
#endif
int mul_candidate(const uint32_t *a,size_t na,const uint32_t *b,size_t nb,uint32_t *out) {
    if (!a || !b || !out || !na || !nb || na>2048 || nb>2048) return 1;
    if ((uintptr_t)a%_Alignof(uint32_t) || (uintptr_t)b%_Alignof(uint32_t) || (uintptr_t)out%_Alignof(uint32_t)) return 1;
    uintptr_t start=(uintptr_t)out, end=start+4*(na+nb);
    if (end<start || (uintptr_t)a>UINTPTR_MAX-4*na || (uintptr_t)b>UINTPTR_MAX-4*nb ||
        ((uintptr_t)a<end && start<(uintptr_t)a+4*na) ||
        ((uintptr_t)b<end && start<(uintptr_t)b+4*nb)) return 1;
    if (a[0]>255 || b[0]>255) return 1;
    for (size_t i=1;i<na;++i) if (a[i]) return 1;
    for (size_t i=1;i<nb;++i) if (b[i]) return 1;
    unsigned char left[8],right[8],product[16];
    for (unsigned i=0;i<8;++i) { left[i]=(unsigned char)('0'+((a[0]>>(7-i))&1)); right[i]=(unsigned char)('0'+((b[0]>>(7-i))&1)); }
    composition_context *context=NULL;
    exact_status status=composition_prepare(REDUCED_ALGEBRA,MB16_RECORD_BUDGET,&context);
    if (status!=EXACT_OK) return 2;
    composition_trace trace={0};
    status=multiply_exact(context,left,8,right,8,product,16,&trace);
    composition_clear(context);
    if (status!=EXACT_OK) return 2;
    /* Necessary observations only. Exact accepted stage/dimension/call contracts
     * are still missing and must be independently checked before admission. */
    if (!trace.stages || !trace.motif_calls || !trace.short_calls) return 3;
    uint32_t word=0;
    for (unsigned i=0;i<16;++i) { if (product[i]!='0' && product[i]!='1') return 3; word=(word<<1)|(uint32_t)(product[i]-'0'); }
    memset(out,0,4*(na+nb)); out[0]=word; return 0;
}
