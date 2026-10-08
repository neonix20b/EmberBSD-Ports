/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), exercise upstream FD counting on NetBSD. */
#define _NETBSD_SOURCE
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int count_open_fds(void);
static unsigned failures;

static void
check(const char *name, int actual, int expected)
{
	printf("%s: %s (actual %d, expected %d)\n",
	    actual == expected ? "PASS" : "FAIL", name, actual, expected);
	failures += actual != expected;
}

static void
exec_check(const char *checker, int cloexec, int leak)
{
	int fd[2], status;
	pid_t child;
	int before = count_open_fds();

	assert(pipe2(fd, cloexec ? O_CLOEXEC : 0) == 0);
	fflush(NULL);
	child = fork();
	assert(child >= 0);
	if (child == 0) {
		char number[32];

		snprintf(number, sizeof(number), "%d",
		    before + (!cloexec && !leak ? 2 : 0));
		execl(checker, checker, number, (char *)NULL);
		_exit(99);
	}
	assert(close(fd[0]) == 0 && close(fd[1]) == 0);
	assert(waitpid(child, &status, 0) == child);
	check(cloexec ? "exec closes CLOEXEC pipe" :
	    leak ? "exec detects unaccounted pipe" : "exec keeps accounted pipe",
	    WIFEXITED(status) ? WEXITSTATUS(status) : -1, leak ? 1 : 0);
}

int
main(int argc, char **argv)
{
	int fd[2], high, status, before;
	struct rlimit limit, lowered;
	pid_t child;

	assert(argc == 2);
	before = count_open_fds();
	check("repeated count opens no descriptors", count_open_fds(), before);
	assert(pipe(fd) == 0);
	check("pipe adds two descriptors", count_open_fds(), before + 2);
	assert(close(fd[0]) == 0);
	check("closing one pipe end subtracts one", count_open_fds(), before + 1);
	assert(close(fd[1]) == 0);
	check("pipe cleanup", count_open_fds(), before);

	assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fd) == 0);
	check("socketpair adds two descriptors", count_open_fds(), before + 2);
	high = fcntl(fd[0], F_DUPFD, 128);
	assert(high >= 128);
	check("sparse high descriptor", count_open_fds(), before + 3);
	assert(getrlimit(RLIMIT_NOFILE, &limit) == 0);
	lowered = limit;
	lowered.rlim_cur = 64;
	assert(setrlimit(RLIMIT_NOFILE, &lowered) == 0);
	check("descriptor above lowered soft limit", count_open_fds(), before + 3);
	assert(setrlimit(RLIMIT_NOFILE, &limit) == 0);
	assert(close(high) == 0 && close(fd[0]) == 0 && close(fd[1]) == 0);
	check("socketpair and duplicate cleanup", count_open_fds(), before);

	fflush(NULL);
	child = fork();
	assert(child >= 0);
	if (child == 0) {
		assert(fcntl(0, F_CLOSEM, 0) == 0);
		_exit(count_open_fds() == 0 ? 0 : 1);
	}
	assert(waitpid(child, &status, 0) == child);
	check("empty descriptor table including closed stdin",
	    WIFEXITED(status) ? WEXITSTATUS(status) : -1, 0);

	exec_check(argv[1], 0, 0);
	exec_check(argv[1], 0, 1);
	exec_check(argv[1], 1, 0);
	printf("FD counter: %u failures\n", failures);
	return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
