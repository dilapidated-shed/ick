#include <stdio.h>

extern int ick_armv7_value(int, int);

int main(void)
{
    int got = ick_armv7_value(5, 9);
    if (got != 62) {
        fprintf(stderr, "FAIL: ICK Thumb-2 returned %d, expected 62\n", got);
        return 1;
    }
    puts("PASS: ICK Thumb-2 executed on Android ARMv7 hardware");
    return 0;
}
