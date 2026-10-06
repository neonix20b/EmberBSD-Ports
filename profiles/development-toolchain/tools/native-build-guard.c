/* SPDX-License-Identifier: BSD-2-Clause */
/* AI-assisted EmberBSD native compiler build supervisor. */

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/wait.h>

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t interrupted;

static void
on_signal(int sig)
{

	interrupted = sig;
}

static int
record_number(int fd, long value)
{
	char buf[64];
	int len, error;

	len = snprintf(buf, sizeof(buf), "%ld\n", value);
	error = write(fd, buf, (size_t)len) != len;
	if (close(fd) == -1)
		error = 1;
	return error ? -1 : 0;
}

static uint64_t
available(const char *path)
{
	struct statvfs fs;

	if (statvfs(path, &fs) == -1 || (int64_t)fs.f_bavail < 0)
		return 0;
	return (uint64_t)fs.f_bavail * (fs.f_frsize / 1024);
}

static int
space_ok(const char *scratch, dev_t device, uint64_t root_min,
    uint64_t scratch_min)
{
	struct stat st;
	uint64_t root_free, scratch_free;

	root_free = available("/");
	scratch_free = available(scratch);
	(void)fprintf(stderr, "space epoch=%jd root_kib=%ju scratch_kib=%ju\n",
	    (intmax_t)time(NULL), (uintmax_t)root_free,
	    (uintmax_t)scratch_free);
	return stat(scratch, &st) == 0 && st.st_dev == device &&
	    root_free >= root_min && scratch_free >= scratch_min;
}

int
main(int argc, char **argv)
{
	struct stat root, scratch, run;
	struct sigaction sa;
	struct timespec delay = { 1, 0 };
	uint64_t root_min, scratch_min;
	pid_t child, result;
	char *end, ready;
	int channel[2], logfd, pidfd, groupfd, statusfd, status, code, tick, i;

	if (argc < 7 || strcmp(argv[5], "--") != 0) {
		(void)fprintf(stderr,
		    "usage: guard run-dir scratch root-kib scratch-kib -- command ...\n");
		return 64;
	}
	errno = 0;
	root_min = strtoull(argv[3], &end, 10);
	if (errno || argv[3][0] < '0' || argv[3][0] > '9' ||
	    *end || root_min < 1048576)
		return 64;
	errno = 0;
	scratch_min = strtoull(argv[4], &end, 10);
	if (errno || argv[4][0] < '0' || argv[4][0] > '9' ||
	    *end || scratch_min < 2097152)
		return 64;
	/* A missing scratch mount must never spill the build onto root. */
	if (argv[2][0] != '/' || stat("/", &root) == -1 ||
	    stat(argv[2], &scratch) == -1 || scratch.st_dev == root.st_dev) {
		(void)fprintf(stderr, "scratch must be a separate mounted filesystem\n");
		return 75;
	}
	/* Caller creates a fresh run directory; never reuse logs or status. */
	if (chdir(argv[1]) == -1 || stat(".", &run) == -1 ||
	    run.st_dev != scratch.st_dev ||
	    (logfd = open("build.log", O_WRONLY | O_CREAT | O_EXCL, 0600)) == -1) {
		perror("run directory/log");
		return 74;
	}
	if (dup2(logfd, STDOUT_FILENO) == -1 ||
	    dup2(logfd, STDERR_FILENO) == -1)
		return 74;
	(void)close(logfd);
	/* Reserve every metadata name before creating any build process. */
	pidfd = open("supervisor.pid", O_WRONLY | O_CREAT | O_EXCL, 0600);
	groupfd = open("child.pgid", O_WRONLY | O_CREAT | O_EXCL, 0600);
	statusfd = open("status", O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (pidfd == -1 || groupfd == -1 || statusfd == -1 ||
	    fcntl(groupfd, F_SETFD, FD_CLOEXEC) == -1 ||
	    fcntl(statusfd, F_SETFD, FD_CLOEXEC) == -1 ||
	    record_number(pidfd, (long)getpid()) == -1)
		return 74;
	if (!space_ok(argv[2], scratch.st_dev, root_min, scratch_min)) {
		(void)record_number(statusfd, 75);
		return 75;
	}
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	(void)sigemptyset(&sa.sa_mask);
	if (sigaction(SIGTERM, &sa, NULL) == -1 ||
	    sigaction(SIGINT, &sa, NULL) == -1 ||
	    sigaction(SIGHUP, &sa, NULL) == -1 || pipe(channel) == -1) {
		(void)record_number(statusfd, 74);
		return 74;
	}
	child = fork();
	if (child == -1) {
		(void)record_number(statusfd, 74);
		return 74;
	}
	if (child == 0) {
		(void)close(channel[0]);
		sa.sa_handler = SIG_DFL;
		(void)sigaction(SIGTERM, &sa, NULL);
		(void)sigaction(SIGINT, &sa, NULL);
		(void)sigaction(SIGHUP, &sa, NULL);
		if (setsid() == -1 || write(channel[1], "R", 1) != 1)
			_exit(126);
		(void)close(channel[1]);
		execvp(argv[6], &argv[6]);
		perror(argv[6]);
		_exit(127);
	}
	(void)close(channel[1]);
	/* Handshake proves the child owns its session before group signalling. */
	do {
		i = (int)read(channel[0], &ready, 1);
	} while (i == -1 && errno == EINTR);
	(void)close(channel[0]);
	if (i != 1 || ready != 'R') {
		while (waitpid(child, &status, 0) == -1 && errno == EINTR)
			continue;
		(void)record_number(statusfd, 126);
		return 126;
	}
	code = record_number(groupfd, (long)child) == -1 ? 74 : 0;
	for (tick = 0;; tick++) {
		result = waitpid(child, &status, WNOHANG);
		if (result == child) {
			if (code != 74)
				code = WIFEXITED(status) ? WEXITSTATUS(status) :
				    128 + WTERMSIG(status);
			break;
		}
		if (result == -1 && errno != EINTR) {
			code = 74;
			break;
		}
		if (code == 74 || interrupted || (tick % 5 == 0 &&
		    !space_ok(argv[2], scratch.st_dev, root_min, scratch_min))) {
			code = code == 74 ? 74 : (interrupted ? 128 + interrupted : 75);
			(void)fprintf(stderr, "stopping own process group %ld: status=%d\n",
			    (long)child, code);
			(void)kill(-child, SIGTERM);
			/* Keep the child unreaped, so its PID cannot be reused. */
			for (i = 0; i < 5; i++)
				(void)nanosleep(&delay, NULL);
			(void)kill(-child, SIGKILL);
			while (waitpid(child, &status, 0) == -1 && errno == EINTR)
				continue;
			break;
		}
		(void)nanosleep(&delay, NULL);
	}
	(void)fprintf(stderr, "finished epoch=%jd status=%d\n",
	    (intmax_t)time(NULL), code);
	if (record_number(statusfd, code) == -1)
		return 74;
	return code;
}
