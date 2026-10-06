#include <sys/types.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(void)
{
    int old_mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, getpid() };
    int new_mib[] = { CTL_KERN, KERN_PROC_ARGS, getpid(), KERN_PROC_PATHNAME };
    char path[4096];
    size_t size = sizeof(path);
    int result = sysctl(old_mib, 4, path, &size, NULL, 0);
    printf("FreeBSD mib: result=%d errno=%d bytes=%zu\n", result, errno, size);
    size = sizeof(path);
    result = sysctl(new_mib, 4, path, &size, NULL, 0);
    printf("NetBSD mib: result=%d path=%s\n", result, result == 0 ? path : strerror(errno));
    return result == 0 ? 0 : 1;
}
