/* SPDX-License-Identifier: MIT */
/* Normalize inherited signal dispositions for lifecycle test children. */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char **argv)
{

	if (argc < 3)
		return 2;
	if (signal(SIGTERM, strcmp(argv[1], "ignore-term") == 0 ?
	    SIG_IGN : SIG_DFL) == SIG_ERR ||
	    signal(SIGHUP, SIG_DFL) == SIG_ERR ||
	    signal(SIGINT, SIG_DFL) == SIG_ERR) {
		perror("signal");
		return 1;
	}
	execvp(argv[2], argv + 2);
	perror(argv[2]);
	return 127;
}
