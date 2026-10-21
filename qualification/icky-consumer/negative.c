#if CASE == 1
int f(void) { return __builtin_icky(010); }
#elif CASE == 2
int f(void) { return __builtin_icky(1 + 2); }
#elif CASE == 3
int f(void) { int x; return __builtin_icky(x ↚ 010); }
#elif CASE == 4
#line 900 "icky-fabricated-location.c"
int f(void) { return __builtin_icky(010); }
#elif CASE == 5
int f(void) { return __builtin_icky("not a noun"); }
#elif CASE == 6
int f(void) { return __builtin_icky(int x); }
#elif CASE == 7
int f(void) { const int x = 0; return __builtin_icky(x ← 10); }
#elif CASE == 8
#define JOIN(a,b) a##b
int f(void) { int xy = 0; return __builtin_icky(JOIN(x,y) ← 10); }
#elif CASE == 9
#line 1 "qualification/icky-consumer/alias.c"
int f(void) { return __builtin_icky(010); }
#elif CASE == 10
# 1 "qualification/icky-consumer/alias.c" 1
int f(void) { return __builtin_icky(010); }
#endif
