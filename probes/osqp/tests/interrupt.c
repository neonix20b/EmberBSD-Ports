/* SPDX-License-Identifier: MIT */
/* Private implementation regression for the unchanged upstream POSIX listener. */
#include <signal.h>
#include <stdio.h>

void osqp_start_interrupt_listener(void);
void osqp_end_interrupt_listener(void);
int osqp_is_interrupted(void);

static volatile sig_atomic_t restored;

static void
previous_handler(int signal_number)
{

	restored = signal_number;
}

int
main(void)
{
	struct sigaction previous, original;
	int detected;

	previous.sa_handler = previous_handler;
	sigemptyset(&previous.sa_mask);
	previous.sa_flags = 0;
	if (sigaction(SIGINT, &previous, &original) != 0)
		return 1;
	osqp_start_interrupt_listener();
	if (osqp_is_interrupted() || raise(SIGINT) != 0)
		return 1;
	detected = osqp_is_interrupted();
	osqp_end_interrupt_listener();
	if (!detected || restored || raise(SIGINT) != 0 || restored != SIGINT)
		return 1;
	if (sigaction(SIGINT, &original, NULL) != 0)
		return 1;
	puts("POSIX listener detected SIGINT and restored the previous handler: PASS");
	return 0;
}
