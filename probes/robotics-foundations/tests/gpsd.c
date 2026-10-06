/* SPDX-License-Identifier: MIT */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <gps.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <util.h>

static pid_t child = -1;
static volatile sig_atomic_t interrupted;

static void
on_signal(int signo)
{
	interrupted = signo;
}

static double
now(void)
{
	struct timespec ts;
	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
		perror("clock_gettime");
		exit(1);
	}
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void
pause_ms(long ms)
{
	struct timespec ts = {ms / 1000, (ms % 1000) * 1000000};
	(void)nanosleep(&ts, NULL);
}

static int
sentence(int fd, const char *body, bool corrupt)
{
	char line[256];
	unsigned char sum = 0;
	const unsigned char *p;
	size_t sent = 0;
	ssize_t n;
	int len;

	for (p = (const unsigned char *)body; *p; p++)
		sum ^= *p;
	if (corrupt)
		sum ^= 0xff;
	len = snprintf(line, sizeof(line), "$%s*%02X\r\n", body, sum);
	if (len < 0 || (size_t)len >= sizeof(line))
		return -1;
	while (sent < (size_t)len && !interrupted) {
		n = write(fd, line + sent, (size_t)len - sent);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			return -1;
		sent += (size_t)n;
	}
	return sent == (size_t)len ? 0 : -1;
}

static int
feed(int fd, int stage, unsigned tick)
{
	char body[200];
	const char *lat = stage == 3 ? "4900.000" : "4807.038";
	bool lost = stage == 2;

	/* A different, plausible position with a deliberately bad checksum. */
	if (stage == 1) {
		snprintf(body, sizeof(body),
		    "GPRMC,1200%02u.00,A,3000.000,N,03100.000,E,0.0,0.0,061026,,,A",
		    tick % 60);
		return sentence(fd, body, true);
	}
	snprintf(body, sizeof(body),
	    "GPGGA,1200%02u.00,%s,N,01131.000,E,%d,08,0.9,545.4,M,46.9,M,,",
	    tick % 60, lat, lost ? 0 : 1);
	if (sentence(fd, body, false) != 0)
		return -1;
	if (sentence(fd, lost ? "GPGSA,A,1,,,,,,,,,,,,,1.8,1.0,1.5" :
	    "GPGSA,A,3,04,05,09,12,24,25,29,31,,,,,1.8,1.0,1.5", false) != 0)
		return -1;
	snprintf(body, sizeof(body),
	    "GPRMC,1200%02u.00,%c,%s,N,01131.000,E,0.0,0.0,061026,,,%c",
	    tick % 60, lost ? 'V' : 'A', lat, lost ? 'N' : 'A');
	return sentence(fd, body, false);
}

int
main(int argc, char **argv)
{
	struct sockaddr_in address;
	struct gps_data_t gps;
	struct termios tio;
	struct sigaction sa;
	socklen_t size = sizeof(address);
	char port[16], device[128];
	int master = -1, slave = -1, sock = -1, status = 0, rc = 1;
	bool connected = false, version = false, first = false;
	bool lost = false, recovered = false, bad = false, no_feed;
	double deadline, start, next_feed, elapsed;
	unsigned tick = 0;
	int stage;

	if ((argc != 2 && argc != 3) || argv[1][0] != '/' ||
	    (argc == 3 && strcmp(argv[2], "--no-feed") != 0)) {
		fprintf(stderr, "Usage: gpsd-contract ABSOLUTE_GPSD [--no-feed]\n");
		return 2;
	}
	no_feed = argc == 3;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigemptyset(&sa.sa_mask);
	(void)sigaction(SIGALRM, &sa, NULL);
	(void)sigaction(SIGINT, &sa, NULL);
	(void)sigaction(SIGTERM, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);
	alarm(25);
	memset(&gps, 0, sizeof(gps));
	if (openpty(&master, &slave, device, NULL, NULL) != 0 ||
	    tcgetattr(slave, &tio) != 0)
		goto done;
	cfmakeraw(&tio);
	if (tcsetattr(slave, TCSANOW, &tio) != 0 ||
	    fcntl(master, F_SETFD, FD_CLOEXEC) != 0 ||
	    fcntl(slave, F_SETFD, FD_CLOEXEC) != 0)
		goto done;
	/* Nonblocking writes prevent a stopped daemon from filling the PTY forever. */
	if (fcntl(master, F_SETFL, O_NONBLOCK) != 0)
		goto done;
	sock = socket(AF_INET, SOCK_STREAM, 0);
	memset(&address, 0, sizeof(address));
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (sock < 0 || bind(sock, (struct sockaddr *)&address, size) != 0 ||
	    getsockname(sock, (struct sockaddr *)&address, &size) != 0)
		goto done;
	snprintf(port, sizeof(port), "%u", ntohs(address.sin_port));
	close(sock);
	sock = -1;
	child = fork();
	if (child < 0)
		goto done;
	if (child == 0) {
		execl(argv[1], argv[1], "-N", "-n", "-b", "-D", "2", "-S", port,
		    device, (char *)NULL);
		perror("exec gpsd");
		_exit(127);
	}
	deadline = now() + 5;
	while (!interrupted && now() < deadline) {
		if (waitpid(child, &status, WNOHANG) == child) {
			child = -1;
			fprintf(stderr, "gpsd exited before connection: %d\n", status);
			goto done;
		}
		if (gps_open("127.0.0.1", port, &gps) == 0) {
			connected = true;
			break;
		}
		pause_ms(50);
	}
	if (!connected || gps_stream(&gps, WATCH_ENABLE | WATCH_JSON, NULL) != 0)
		goto done;
	start = next_feed = now();
	while (!interrupted && (elapsed = now() - start) < 12) {
		stage = elapsed < 3 ? 0 : elapsed < 5 ? 1 : elapsed < 8 ? 2 : 3;
		if (!no_feed && now() >= next_feed) {
			if (feed(master, stage, tick++) != 0)
				goto done;
			next_feed = now() + 0.2;
		}
		if (waitpid(child, &status, WNOHANG) == child) {
			child = -1;
			fprintf(stderr, "gpsd exited during replay: %d\n", status);
			goto done;
		}
		if (!gps_waiting(&gps, 50000))
			continue;
		if (gps_read(&gps, NULL, 0) < 0)
			goto done;
		if (gps.set & VERSION_SET)
			version = strcmp(gps.version.release, "3.27.5") == 0;
		if ((gps.set & LATLON_SET) && isfinite(gps.fix.latitude) &&
		    fabs(gps.fix.latitude - 30) < 1e-6)
			bad = true;
		if (stage == 0 && (gps.set & LATLON_SET) && gps.fix.mode == MODE_3D &&
		    fabs(gps.fix.latitude - 48.1173) < 1e-6 &&
		    fabs(gps.fix.longitude - 11.5166666667) < 1e-6 &&
		    fabs(gps.fix.altMSL - 545.4) < 1e-3)
			first = true;
		if (stage == 2 && (gps.set & MODE_SET) && gps.fix.mode == MODE_NO_FIX)
			lost = true;
		if (stage == 3 && (gps.set & LATLON_SET) && gps.fix.mode == MODE_3D &&
		    fabs(gps.fix.latitude - 49) < 1e-6 &&
		    fabs(gps.fix.longitude - 11.5166666667) < 1e-6)
			recovered = true;
	}
	printf("gpsd 3.27.5: version=%d fix=%d bad_checksum_accepted=%d loss=%d recovery=%d\n",
	    version, first, bad, lost, recovered);
	if (!interrupted && version && first && !bad && lost && recovered)
		rc = 0;
done:
	if (rc != 0)
		fprintf(stderr, "gpsd probe failed (last OS error: %s)\n", strerror(errno));
	if (connected)
		(void)gps_close(&gps);
	if (child > 0) {
		(void)kill(child, SIGTERM);
		deadline = now() + 1;
		while (waitpid(child, &status, WNOHANG) == 0 && now() < deadline)
			pause_ms(20);
		if (waitpid(child, &status, WNOHANG) == 0) {
			(void)kill(child, SIGKILL);
			(void)waitpid(child, &status, 0);
		}
	}
	if (master >= 0) close(master);
	if (slave >= 0) close(slave);
	if (sock >= 0) close(sock);
	alarm(0);
	puts(rc == 0 ? "PASS gpsd PTY/libgps contract" : "FAIL gpsd PTY/libgps contract");
	return rc;
}
