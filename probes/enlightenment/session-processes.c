/* SPDX-License-Identifier: BSD-2-Clause */
/* Scoped cleanup for a disposable Enlightenment session on NetBSD. */
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/stat.h>

#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MARKER "EMBERBSD_ENLIGHTENMENT_SESSION"
#define MAX_ENV_BYTES (16U * 1024U * 1024U)
#define MAX_PROC_BYTES (64U * 1024U * 1024U)
#define SCAN_ATTEMPTS 4

static uid_t owner;
static pid_t self, parent;
static bool incomplete;

static void
problem(const char *operation, pid_t pid)
{
	if (pid > 0)
		fprintf(stderr, "session-processes: %s (pid %ld): %s\n",
		    operation, (long)pid, strerror(errno));
	else
		fprintf(stderr, "session-processes: %s: %s\n",
		    operation, strerror(errno));
	incomplete = true;
}

static bool
eligible(const struct kinfo_proc2 *p)
{
	/* p_uvalid excludes exited processes without usable start-time data. */
	return p->p_pid > 1 && p->p_pid != self && p->p_pid != parent &&
	    p->p_uid == owner && p->p_ruid == owner && p->p_svuid == owner &&
	    p->p_uvalid != 0 && (p->p_realflag & P_SYSTEM) == 0;
}

static bool
same_process(const struct kinfo_proc2 *a, const struct kinfo_proc2 *b)
{
	return eligible(b) && a->p_pid == b->p_pid &&
	    a->p_ustart_sec == b->p_ustart_sec &&
	    a->p_ustart_usec == b->p_ustart_usec;
}

static struct kinfo_proc2 *
processes(size_t *count)
{
	int mib[] = { CTL_KERN, KERN_PROC2, KERN_PROC_UID, (int)owner,
	    sizeof(struct kinfo_proc2), 0 };
	struct kinfo_proc2 *list;
	size_t bytes, capacity;
	unsigned int attempt;

	for (attempt = 0; attempt < SCAN_ATTEMPTS; attempt++) {
		bytes = 0;
		if (sysctl(mib, 6, NULL, &bytes, NULL, 0) == -1) {
			problem("size process table", 0);
			return NULL;
		}
		/* Allow process creation between sizing and reading the table. */
		if (bytes > MAX_PROC_BYTES - 32 * sizeof(*list)) {
			errno = E2BIG;
			problem("process table limit", 0);
			return NULL;
		}
		capacity = bytes + 32 * sizeof(*list);
		list = malloc(capacity);
		if (list == NULL) {
			problem("allocate process table", 0);
			return NULL;
		}
		mib[5] = (int)(capacity / sizeof(*list));
		bytes = capacity;
		if (sysctl(mib, 6, list, &bytes, NULL, 0) == 0) {
			if (bytes > capacity || bytes % sizeof(*list) != 0) {
				free(list);
				errno = EIO;
				problem("invalid process table length", 0);
				return NULL;
			}
			*count = bytes / sizeof(*list);
			return list;
		}
		free(list);
		if (errno != ENOMEM && errno != EINTR) {
			problem("read process table", 0);
			return NULL;
		}
	}
	errno = EBUSY;
	problem("process table changed repeatedly", 0);
	return NULL;
}

static bool
revalidate(const struct kinfo_proc2 *original)
{
	struct kinfo_proc2 current;
	int mib[] = { CTL_KERN, KERN_PROC2, KERN_PROC_PID, original->p_pid,
	    sizeof(current), 1 };
	size_t bytes = sizeof(current);

	if (sysctl(mib, 6, &current, &bytes, NULL, 0) == -1) {
		if (errno != ESRCH && errno != EINVAL)
			problem("recheck process", original->p_pid);
		return false;
	}
	return bytes == sizeof(current) && same_process(original, &current);
}

static bool
has_marker(pid_t pid, const char *token)
{
	int mib[] = { CTL_KERN, KERN_PROC_ARGS, pid, KERN_PROC_ENV };
	char *env, *end;
	size_t capacity, bytes, offset, length, wanted = strlen(token);
	bool match;
	unsigned int attempt;

	capacity = 0;
	if (sysctl(mib, 4, NULL, &capacity, NULL, 0) == -1) {
		/* An exiting process can disappear between table and environment reads. */
		if (errno != ESRCH && errno != EINVAL)
			problem("size environment", pid);
		return false;
	}
	if (capacity == 0)
		return false;
	for (attempt = 0; capacity <= MAX_ENV_BYTES; attempt++) {
		env = malloc(capacity);
		if (env == NULL) {
			problem("allocate environment buffer", pid);
			return false;
		}
		bytes = capacity;
		if (sysctl(mib, 4, env, &bytes, NULL, 0) == -1) {
			free(env);
			if ((errno == EBUSY || errno == EINTR) &&
			    attempt + 1 < SCAN_ATTEMPTS)
				continue;
			if (errno != ESRCH && errno != EINVAL)
				problem("read environment", pid);
			return false;
		}
		/* NetBSD can successfully return truncated environment data. */
		if (bytes >= capacity) {
			free(env);
			capacity *= 2;
			continue;
		}
		match = false;
		for (offset = 0; offset < bytes; offset += length + 1) {
			end = memchr(env + offset, '\0', bytes - offset);
			if (end == NULL) {
				free(env);
				errno = EIO;
				problem("unterminated environment token", pid);
				return false;
			}
			length = (size_t)(end - (env + offset));
			if (length == wanted &&
			    memcmp(env + offset, token, wanted) == 0)
				match = true;
		}
		free(env);
		return match;
	}
	errno = E2BIG;
	problem("environment exceeds inspection limit", pid);
	return false;
}

int
main(int argc, char **argv)
{
	struct kinfo_proc2 *list;
	struct stat st;
	const char *marker;
	char token[sizeof(MARKER) + PATH_MAX];
	size_t count, i;
	int sig = 0, found = 0;

	if (argc == 2 && strcmp(argv[1], "--check") == 0)
		sig = 0;
	else if (argc == 3 && strcmp(argv[1], "--signal") == 0 &&
	    strcmp(argv[2], "TERM") == 0)
		sig = SIGTERM;
	else if (argc == 3 && strcmp(argv[1], "--signal") == 0 &&
	    strcmp(argv[2], "KILL") == 0)
		sig = SIGKILL;
	else {
		fprintf(stderr, "Usage: session-processes --check | --signal TERM|KILL\n");
		return 2;
	}
	owner = getuid();
	self = getpid();
	parent = getppid();
	if (owner == 0 || geteuid() != owner || getgid() != getegid()) {
		fprintf(stderr, "session-processes: requires an unprivileged, non-setid caller\n");
		return 2;
	}
	marker = getenv(MARKER);
	if (marker == NULL || marker[0] != '/' || marker[1] == '\0' ||
	    strlen(marker) >= PATH_MAX) {
		fprintf(stderr, "session-processes: marker must be an absolute session directory\n");
		return 2;
	}
	if (lstat(marker, &st) == -1) {
		problem("stat session directory", 0);
		return 2;
	}
	if (!S_ISDIR(st.st_mode) || st.st_uid != owner || (st.st_mode & 0022)) {
		fprintf(stderr, "session-processes: session directory must be owned by caller and not writable by group/others\n");
		return 2;
	}
	(void)snprintf(token, sizeof(token), "%s=%s", MARKER, marker);
	list = processes(&count);
	if (list == NULL)
		return 2;
	for (i = 0; i < count; i++) {
		if (!eligible(&list[i]) || !revalidate(&list[i]) ||
		    !has_marker(list[i].p_pid, token) || !revalidate(&list[i]))
			continue;
		if (sig != 0 && kill(list[i].p_pid, sig) == -1) {
			if (errno != ESRCH)
				problem("signal process", list[i].p_pid);
			continue;
		}
		found = 1;
		printf("%ld\n", (long)list[i].p_pid);
	}
	free(list);
	return incomplete ? 2 : (found ? 0 : 1);
}
