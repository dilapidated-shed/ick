#include <stdio.h>
#include <string.h>
/* Test double only: never an admitted compiler in a producer receipt. */
int main(int argc,char **argv)
{
    if(argc==2 && !strcmp(argv[1],"--version")) { puts("failure fixture (GCC)"); return 0; }
    if(argc==2 && !strcmp(argv[1],"-dumpmachine")) { puts("arm-linux-gnueabi"); return 0; }
    fputs("error: deliberately failed ICK compilation\n",stderr);
    return 43;
}
