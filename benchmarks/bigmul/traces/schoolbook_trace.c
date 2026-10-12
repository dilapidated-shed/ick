/* Executed schoolbook control. Logical array coordinates, not physical traffic. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
static size_t sequence;
static size_t event(const char *kind,const char *buffer,size_t index,uint64_t value,
                    const char *dependencies,unsigned bits,const char *units) {
    size_t current=sequence++;
    printf("%zu\t%s\t%s\t%zu\t%" PRIu64 "\t%s\t%u\t%s\n",
           current,kind,buffer,index,value,dependencies,bits,units);
    return current;
}
int main(int argc,char **argv) {
    if(argc<8) return 2;
    char *end;
    size_t na=(size_t)strtoul(argv[4],&end,10); if(*end || !na || na>16) return 2;
    size_t nb=(size_t)strtoul(argv[5],&end,10); if(*end || !nb || nb>16) return 2;
    if((size_t)argc!=6+na+nb) return 2;
    uint32_t a[16],b[16],out[32];
    size_t a_write[16],b_write[16],out_write[32];
    for(size_t k=0;k<na+nb;++k) {
        unsigned long long value=strtoull(argv[6+k],&end,10);
        if(*end || value>UINT32_MAX) return 2;
        if(k<na) a[k]=(uint32_t)value; else b[k-na]=(uint32_t)value;
    }
    printf("trace-v1\nsource_sha256\t%s\nbinary_sha256\t%s\ncase_sha256\t%s\n",
           argv[1],argv[2],argv[3]);
    puts("profile\texecuted-schoolbook-control\ncomplete\t1\ncoordinate_space\tlogical-limb-index");
    puts("seq\tkind\tbuffer\tindex\tvalue\tdependencies\tword_bits\tunits");
    event("allocate","a",0,na,"-",32,"limbs");
    event("allocate","b",0,nb,"-",32,"limbs");
    event("allocate","out",0,na+nb,"-",32,"limbs");
    for(size_t i=0;i<na;++i) a_write[i]=event("write","a",i,a[i],"-",32,"value");
    for(size_t i=0;i<nb;++i) b_write[i]=event("write","b",i,b[i],"-",32,"value");
    for(size_t i=0;i<na+nb;++i) { out[i]=0; out_write[i]=event("write","out",i,out[i],"-",32,"value"); }
    for(size_t i=0;i<na;++i) {
        uint64_t carry=0; size_t carry_event=SIZE_MAX;
        for(size_t j=0;j<nb;++j) {
            char prior[32];
            snprintf(prior,sizeof(prior),"%zu",a_write[i]);
            size_t ar=event("read","a",i,a[i],prior,32,"value");
            snprintf(prior,sizeof(prior),"%zu",b_write[j]);
            size_t br=event("read","b",j,b[j],prior,32,"value");
            snprintf(prior,sizeof(prior),"%zu",out_write[i+j]);
            size_t old=event("read","out",i+j,out[i+j],prior,32,"value");
            uint64_t intermediate=(uint64_t)a[i]*b[j]+out[i+j]+carry;
            char dependencies[128];
            if(carry_event==SIZE_MAX) snprintf(dependencies,sizeof(dependencies),"%zu,%zu,%zu",ar,br,old);
            else snprintf(dependencies,sizeof(dependencies),"%zu,%zu,%zu,%zu",ar,br,old,carry_event);
            size_t mac=event("multiply-accumulate","out",i+j,intermediate,dependencies,64,"value");
            snprintf(dependencies,sizeof(dependencies),"%zu",mac);
            out[i+j]=(uint32_t)intermediate;
            out_write[i+j]=event("write","out",i+j,out[i+j],dependencies,32,"value");
            carry=intermediate>>32;
            carry_event=event("carry","out",i+j,carry,dependencies,32,"value");
        }
        char dependency[32]; snprintf(dependency,sizeof(dependency),"%zu",carry_event);
        out[i+nb]=(uint32_t)carry;
        out_write[i+nb]=event("write","out",i+nb,out[i+nb],dependency,32,"value");
    }
    for(size_t i=0;i<na+nb;++i) {
        char prior[32]; snprintf(prior,sizeof(prior),"%zu",out_write[i]);
        event("result","out",i,out[i],prior,32,"value");
    }
    event("free","a",0,0,"-",32,"limbs");
    event("free","b",0,0,"-",32,"limbs");
    event("free","out",0,0,"-",32,"limbs");
    event("end","-",0,na*nb,"-",32,"operations");
    return ferror(stdout) ? 3 : 0;
}
