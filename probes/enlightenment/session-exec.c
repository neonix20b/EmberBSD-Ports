/* NetBSD supplies setsid(2), but no setsid utility. */
#include <sys/types.h>
#include <stdio.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	if (argc < 2)
		return 2;
	if (setsid() == -1) {
		perror("setsid");
		return 1;
	}
	execvp(argv[1], argv + 1);
	perror(argv[1]);
	return 127;
}
