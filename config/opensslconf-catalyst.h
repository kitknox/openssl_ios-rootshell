#if defined(__x86_64__)
#include "opensslconf_x86_64.h"
#elif defined(__aarch64__) || defined(__arm64__)
#include "opensslconf_arm64.h"
#else
#error "Unsupported architecture for Mac Catalyst OpenSSL build"
#endif
