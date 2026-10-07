/* SPDX-License-Identifier: MIT */
#include "network.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/socket.h>
int
main(void)
{
	struct sockaddr_in addr;
	socklen_t len = sizeof(addr);
	emu_socket fd = emu_socket_listen(0, 1, true);
	if (fd == EMU_INVALID_SOCKET || getsockname(fd, (struct sockaddr *)&addr, &len) != 0)
		return 1;
	emu_socket_close(fd);
	if (addr.sin_family != AF_INET || addr.sin_addr.s_addr != htonl(INADDR_LOOPBACK))
		return 1;
	puts("PASS emulator listener binds 127.0.0.1, with an ephemeral port");
	return 0;
}
