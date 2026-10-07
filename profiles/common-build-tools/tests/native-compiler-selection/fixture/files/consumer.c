#include <stdio.h>
#if __GNUC__ != 16 || __GNUC_MINOR__ != 2
#error The actual pkgsrc C wrapper did not select GCC 16.2
#endif
int main(void) { puts("PASS: native pkgsrc C wrapper GCC 16.2"); return 0; }
