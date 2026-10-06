#include <stdint.h>
#include <string.h>
#include <android/native_activity.h>
uint32_t bionic_application_headers(const char *text) { return (uint32_t)strlen(text); }
