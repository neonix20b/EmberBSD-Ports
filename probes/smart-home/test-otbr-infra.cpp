/* SPDX-License-Identifier: BSD-2-Clause */
/* AI-assisted native kernel contract for an extracted upstream constructor. */
#include <sys/socket.h>
#include <sys/wait.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/icmp6.h>
#include <fcntl.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lib/platform/exit_code.h"

static const int kSocketBlock = 0;

static int
SocketWithCloseExec(int domain, int type, int protocol, int)
{

	return socket(domain, type | SOCK_CLOEXEC, protocol);
}

#undef VerifyOrDie
#define VerifyOrDie(condition, code) do { \
	if (!(condition)) { perror(#condition); exit(code); } \
} while (0)

/* Only the platform wrapper above is a fixture; the tested function is upstream. */
#include "constructor.inc"

static void
check(bool condition, const char *label)
{

	if (!condition) {
		(void)fprintf(stderr, "FAIL: %s\n", label);
		exit(1);
	}
	(void)printf("PASS: %s\n", label);
}

static int
option(int fd, int name)
{
	int value = -1;
	socklen_t length = sizeof(value);

	check(getsockopt(fd, IPPROTO_IPV6, name, &value, &length) == 0,
	    "get IPv6 socket option");
	check(length == sizeof(value), "IPv6 option length");
	return value;
}

int
main(void)
{
	struct in6_pktinfo info;
	struct icmp6_filter filter;
	socklen_t length;
	pid_t child;
	int fd, status;

	if (geteuid() != 0) {
		(void)fprintf(stderr, "Root required for a raw ICMPv6 socket.\n");
		return 2;
	}
	fd = CreateIcmp6Socket("lo0");
	check(fd >= 0, "real ICMPv6 socket created");
	memset(&info, 0, sizeof(info));
	length = sizeof(info);
	check(getsockopt(fd, IPPROTO_IPV6, IPV6_PKTINFO, &info, &length) == 0,
	    "read sticky packet information");
	check(length == sizeof(info) && info.ipi6_ifindex == if_nametoindex("lo0"),
	    "selected interface is loopback");
	check(IN6_IS_ADDR_UNSPECIFIED(&info.ipi6_addr), "kernel chooses source address");
	check(BindIcmp6SocketToInterface(fd, UINT_MAX) == -1 && errno == ENXIO,
	    "interface rebind preserves invalid-index failure");
	check(BindIcmp6SocketToInterface(fd, if_nametoindex("lo0")) == 0,
	    "interface rebind uses the same native packet-info operation");
	check(option(fd, IPV6_RECVPKTINFO) == 1, "receive interface information");
	check(option(fd, IPV6_RECVHOPLIMIT) == 1, "receive hop limit");
	check(option(fd, IPV6_UNICAST_HOPS) == 255, "unicast ND hop limit");
	check(option(fd, IPV6_MULTICAST_HOPS) == 255, "multicast ND hop limit");
	check(option(fd, IPV6_CHECKSUM) == 2, "kernel ICMPv6 checksum offset");
	length = sizeof(filter);
	check(getsockopt(fd, IPPROTO_ICMPV6, ICMP6_FILTER, &filter, &length) == 0,
	    "read ICMPv6 filter");
	check(ICMP6_FILTER_WILLPASS(ND_ROUTER_SOLICIT, &filter) &&
	    ICMP6_FILTER_WILLPASS(ND_ROUTER_ADVERT, &filter) &&
	    ICMP6_FILTER_WILLPASS(ND_NEIGHBOR_ADVERT, &filter) &&
	    ICMP6_FILTER_WILLBLOCK(ICMP6_ECHO_REQUEST, &filter), "ND-only filter retained");
	check(close(fd) == 0, "socket closed");
	(void)fflush(stdout);
	child = fork();
	if (child == 0) {
		(void)CreateIcmp6Socket("ember-no-such-if");
		_exit(0);
	}
	check(child > 0, "invalid-interface child created");
	check(waitpid(child, &status, 0) == child, "invalid-interface child reaped");
	check(WIFEXITED(status) && WEXITSTATUS(status) == OT_EXIT_INVALID_ARGUMENTS,
	    "invalid interface rejected");
	return 0;
}
