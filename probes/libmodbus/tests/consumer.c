/* SPDX-License-Identifier: MIT */
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#define _NETBSD_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <modbus/modbus.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <util.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t server_pid = -1;
static int completion_fd = -1;
static void stop(int sig)
{
    if (server_pid > 0) {
        kill((pid_t)server_pid, SIGKILL);
        while (waitpid((pid_t)server_pid, NULL, 0) < 0 && errno == EINTR) {}
    }
    _exit(128 + sig);
}
static void fail(const char *what, int line)
{
    int saved = errno;
    if (server_pid > 0) {
        kill((pid_t)server_pid, SIGKILL);
        while (waitpid((pid_t)server_pid, NULL, 0) < 0 && errno == EINTR) {}
    }
    fprintf(stderr, "line %d: %s: %s\n", line, what, modbus_strerror(saved));
    exit(1);
}
#define CHECK(x) do { if (!(x)) fail(#x, __LINE__); } while (0)
static uint64_t micros(void)
{
    struct timespec now;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (uint64_t)now.tv_sec * 1000000 + (uint64_t)now.tv_nsec / 1000;
}
static void setup(modbus_t *ctx)
{
    CHECK(ctx != NULL);
    CHECK(modbus_set_slave(ctx, 1) == 0);
    CHECK(modbus_set_response_timeout(ctx, 0, 150000) == 0);
    CHECK(modbus_set_byte_timeout(ctx, 0, 150000) == 0);
    CHECK(modbus_set_indication_timeout(ctx, 2, 0) == 0);
}
static void reap(void)
{
    int status;
    struct timespec tick = {0, 10000000};
    for (unsigned i = 0; i < 300; ++i) {
        pid_t result = waitpid((pid_t)server_pid, &status, WNOHANG);
        CHECK(result >= 0);
        if (result > 0) {
            server_pid = -1;
            CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
            return;
        }
        CHECK(nanosleep(&tick, NULL) == 0);
    }
    errno = ETIMEDOUT; fail("server did not terminate", __LINE__);
}
static void serve(modbus_t *ctx, int listener, int tcp, int completed)
{
    uint8_t request[MODBUS_MAX_ADU_LENGTH];
    modbus_mapping_t *mapping = modbus_mapping_new(8, 8, 16, 16);
    unsigned requests = 0, silenced = 0;
    CHECK(mapping != NULL);
    for (unsigned session = 0; session < (tcp ? 2U : 1U); ++session) {
        if (tcp) CHECK(modbus_tcp_accept(ctx, &listener) >= 0);
        for (unsigned i = 0; i < (tcp ? (session == 0 ? 4U : 1U) : 5U); ++i) {
            int size = modbus_receive(ctx, request);
            int h = modbus_get_header_length(ctx);
            CHECK(size > h + 2);
            ++requests;
            /* Simulate a silent device on an otherwise valid holding register. */
            if (request[h] == MODBUS_FC_READ_HOLDING_REGISTERS && request[h+1] == 0 && request[h+2] == 15) {
                ++silenced;
                if (tcp) {
                    /* Preserve the connection until the timed-out client closes it. */
                    CHECK(modbus_receive(ctx, request) == -1 && errno == ECONNRESET);
                }
            } else {
                CHECK(modbus_reply(ctx, request, size, mapping) > 0);
            }
        }
        if (tcp) modbus_close(ctx);
    }
    CHECK(requests == 5 && silenced == 1 && mapping->tab_registers[2] == 0x1234 && mapping->tab_registers[3] == 0xabcd);
    {
        char byte;
        CHECK(read(completed, &byte, 1) == 1 && byte == 'D');
        close(completed);
    }
    if (!tcp) modbus_close(ctx);
    if (tcp) close(listener);
    modbus_mapping_free(mapping); modbus_free(ctx);
    _exit(0);
}
static void exercise(modbus_t *client)
{
    uint16_t values[] = {0x1234, 0xabcd}, readback[2] = {0};
    uint64_t start, elapsed;
    CHECK(modbus_connect(client) == 0);
    CHECK(modbus_write_registers(client, 2, 2, values) == 2);
    CHECK(modbus_read_registers(client, 2, 2, readback) == 2);
    CHECK(memcmp(values, readback, sizeof(values)) == 0);
    errno = 0;
    CHECK(modbus_read_registers(client, 100, 1, readback) == -1 && errno == EMBXILADD);
    start = micros(); errno = 0;
    CHECK(modbus_read_registers(client, 15, 1, readback) == -1 && errno == ETIMEDOUT);
    elapsed = micros() - start;
    CHECK(elapsed >= 100000 && elapsed < 1500000);
    modbus_close(client);
    CHECK(modbus_connect(client) == 0);
    memset(readback, 0, sizeof(readback));
    CHECK(modbus_read_registers(client, 2, 2, readback) == 2);
    CHECK(memcmp(values, readback, sizeof(values)) == 0);
    modbus_close(client); modbus_free(client);
    CHECK(write(completion_fd, "D", 1) == 1);
    close(completion_fd); completion_fd = -1;
    reap();
}
static void tcp_test(void)
{
    modbus_t *server = modbus_new_tcp("127.0.0.1", 0), *client;
    struct sockaddr_in address;
    socklen_t size = sizeof(address);
    int listener, completed[2];
    setup(server);
    listener = modbus_tcp_listen(server, 2);
    CHECK(listener >= 0);
    CHECK(getsockname(listener, (struct sockaddr *)&address, &size) == 0);
    client = modbus_new_tcp("127.0.0.1", ntohs(address.sin_port)); setup(client);
    CHECK(pipe(completed) == 0);
    server_pid = fork(); CHECK(server_pid >= 0);
    if (server_pid == 0) { server_pid = -1; alarm(8); close(completed[1]); modbus_free(client); serve(server, listener, 1, completed[0]); }
    close(completed[0]); completion_fd = completed[1];
    close(listener); modbus_free(server);
    exercise(client);
    puts("PASS libmodbus TCP loopback register write/read invalid address timeout reconnect");
}
static void rtu_test(void)
{
    int master, keeper, completed[2];
    char name[256];
    struct termios tty;
    modbus_t *server, *client;
    CHECK(openpty(&master, &keeper, name, NULL, NULL) == 0);
    CHECK(tcgetattr(keeper, &tty) == 0);
    cfmakeraw(&tty);
    CHECK(tcsetattr(keeper, TCSANOW, &tty) == 0);
    server = modbus_new_rtu(name, 19200, 'N', 8, 1); setup(server);
    client = modbus_new_rtu(name, 19200, 'N', 8, 1); setup(client);
    /* Master is an existing byte transport; the client uses real RTU connect/termios on the slave. */
    CHECK(modbus_set_socket(server, master) == 0);
    CHECK(pipe(completed) == 0);
    server_pid = fork(); CHECK(server_pid >= 0);
    if (server_pid == 0) { server_pid = -1; alarm(8); close(completed[1]); close(keeper); modbus_free(client); serve(server, -1, 0, completed[0]); }
    close(completed[0]); completion_fd = completed[1];
    close(master); modbus_free(server);
    /* Keep the slave open so reconnect cannot destroy this test's private PTY. */
    exercise(client);
    close(keeper);
    puts("PASS libmodbus PTY RTU register write/read invalid address timeout reconnect");
}
int main(void)
{
    signal(SIGALRM, stop); signal(SIGINT, stop); signal(SIGTERM, stop);
    signal(SIGPIPE, SIG_IGN);
    alarm(20);
    CHECK(strcmp(LIBMODBUS_VERSION_STRING, "3.2.0") == 0);
    CHECK(libmodbus_version_major == 3 && libmodbus_version_minor == 2 && libmodbus_version_micro == 0);
    tcp_test(); rtu_test();
    alarm(0);
    return 0;
}
