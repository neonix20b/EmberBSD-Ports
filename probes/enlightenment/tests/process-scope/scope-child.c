/* SPDX-License-Identifier: BSD-2-Clause */
/* Bounded native fixture: no GUI, no system services, no broad process signals. */
#include <sys/types.h>
#include <err.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	FILE *f;
	pid_t pid;
	char temporary[4096];

	if (argc != 3)
		errx(2, "Usage: scope-child normal|orphan|ignore PID_FILE");
	(void)alarm(60);
	if (strcmp(argv[1], "orphan") == 0) {
		pid = fork();
		if (pid == -1)
			err(1, "fork");
		if (pid != 0)
			return 0;
		if (setsid() == -1)
			err(1, "setsid");
		(void)alarm(60);
	} else if (strcmp(argv[1], "ignore") == 0) {
		if (signal(SIGTERM, SIG_IGN) == SIG_ERR)
			err(1, "signal");
	} else if (strcmp(argv[1], "normal") != 0)
		errx(2, "unknown fixture mode");
	if (snprintf(temporary, sizeof(temporary), "%s.%ld", argv[2],
	    (long)getpid()) >= (int)sizeof(temporary))
		errx(2, "PID file too long");
	f = fopen(temporary, "wx");
	if (f == NULL)
		err(1, "create PID file");
	fprintf(f, "%ld %ld %ld\n", (long)getpid(), (long)getpgrp(),
	    (long)getsid(0));
	if (fclose(f) != 0 || rename(temporary, argv[2]) == -1)
		err(1, "publish PID file");
	for (;;)
		pause();
}
