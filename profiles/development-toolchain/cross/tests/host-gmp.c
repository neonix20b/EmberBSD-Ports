/* SPDX-License-Identifier: BSD-2-Clause */
/* Exercise long GMP loops across normal scheduling and signal delivery. */
#include <sys/time.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include <gmp.h>

static volatile sig_atomic_t ticks;

static void
tick(int sig)
{

	(void)sig;
	++ticks;
}

int
main(int argc, char **argv)
{
	const size_t n = 1024 * 1024;
	mp_limb_t *a, *b, *result, carry;
	struct sigaction sa = {0};
	struct itimerval timer = {{0, 1000}, {0, 1000}};
	size_t i;
	int k;

	(void)argv;
	a = malloc(n * sizeof(*a));
	b = malloc(n * sizeof(*b));
	result = malloc(n * sizeof(*result));
	if (a == NULL || b == NULL || result == NULL)
		return 2;
	for (i = 0; i < n; ++i) {
		a[i] = ~(mp_limb_t)0;
		b[i] = 1;
	}
	if (argc > 1) {
		sa.sa_handler = tick;
		sigemptyset(&sa.sa_mask);
		if (sigaction(SIGALRM, &sa, NULL) ||
		    setitimer(ITIMER_REAL, &timer, NULL))
			return 2;
	}
	for (k = 0; k < 100; ++k) {
		carry = mpn_add_n(result, a, b, n);
		if (carry != 1 || result[0] != 0 || result[n - 1] != 1)
			return 1;
	}
	if (argc > 1 && ticks == 0)
		return 1;
	printf("PASS: GMP %s, timer=%d, signals=%d\n",
	    gmp_version, argc > 1, (int)ticks);
	free(result);
	free(b);
	free(a);
	return 0;
}
