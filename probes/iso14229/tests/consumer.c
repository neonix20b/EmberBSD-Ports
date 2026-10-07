/* SPDX-License-Identifier: MIT */
#define _POSIX_C_SOURCE 200809L
#include <iso14229.h>
#include <stdarg.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
struct frame { uint32_t id; uint8_t size, bytes[8]; };
static struct frame queue[256];
static size_t head, tail;
static unsigned counts[2][4];
static int drop_requests, idle, responses;
static UDSErr_t last_error;
static UDSTpISOTpC_t client_tp, server_tp;
static UDSClient_t client;
static UDSServer_t server;
static uint8_t value[64];

static uint64_t micros(void)
{
    struct timespec now;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (uint64_t)now.tv_sec * 1000000 + (uint64_t)now.tv_nsec / 1000;
}
uint32_t isotp_user_get_us(void) { return (uint32_t)micros(); }
void isotp_user_debug(const char *message, ...)
{
    va_list ap;
    va_start(ap, message); vfprintf(stderr, message, ap); va_end(ap);
}
int isotp_user_send_can(uint32_t id, const uint8_t *data, uint8_t size, void *arg)
{
    (void)arg;
    struct frame *frame;
    unsigned kind = data[0] >> 4;
    CHECK(size > 0 && size <= 8 && (id == 0x700 || id == 0x708));
    CHECK(kind < 4);
    counts[id == 0x708][kind]++;
    if (drop_requests && id == 0x700) return ISOTP_RET_OK;
    CHECK(tail - head < 256);
    frame = &queue[tail++ % 256];
    frame->id = id; frame->size = size; memcpy(frame->bytes, data, size);
    return ISOTP_RET_OK;
}
static void deliver(void)
{
    unsigned delivered = 0;
    while (head != tail) {
        struct frame frame = queue[head++ % 256];
        CHECK(++delivered < 256);
        isotp_on_can_message(frame.id == 0x700 ? &server_tp.phys_link : &client_tp.phys_link,
            frame.bytes, frame.size);
    }
}
static UDSErr_t server_event(UDSServer_t *srv, UDSEvent_t event, void *arg)
{
    if (event == UDS_EVT_ReadDataByIdent) {
        UDSRDBIArgs_t *read = arg;
        if (read->dataId != 0xf190) return UDS_NRC_RequestOutOfRange;
        return read->copy(srv, value, sizeof(value));
    }
    if (event == UDS_EVT_WriteDataByIdent) {
        UDSWDBIArgs_t *write = arg;
        if (write->dataId != 0xf190) return UDS_NRC_RequestOutOfRange;
        if (write->len != sizeof(value)) return UDS_NRC_IncorrectMessageLengthOrInvalidFormat;
        memcpy(value, write->data, sizeof(value));
        return UDS_OK;
    }
    if (event == UDS_EVT_Err) CHECK(0);
    return UDS_NRC_ServiceNotSupported;
}
static int client_event(UDSClient_t *cli, UDSEvent_t event, void *arg)
{
    (void)cli;
    if (event == UDS_EVT_Idle) idle = 1;
    if (event == UDS_EVT_ResponseReceived) ++responses;
    if (event == UDS_EVT_Err) last_error = *(UDSErr_t *)arg;
    return 0;
}
static void begin(void) { idle = responses = 0; last_error = UDS_OK; }
static void complete(void)
{
    struct timespec tick = {0, 1000000};
    for (unsigned i = 0; i < 2000 && !idle; ++i) {
        UDSErr_t err;
        deliver();
        UDSServerPoll(&server);
        deliver();
        err = UDSClientPoll(&client);
        if (err != UDS_OK) last_error = err;
        CHECK(nanosleep(&tick, NULL) == 0);
    }
    CHECK(idle);
    CHECK(head == tail);
}
int main(void)
{
    uint8_t written[64], read_back[64];
    uint16_t did = 0xf190, unknown = 0xdead;
    UDSRDBIVar_t var = {0xf190, sizeof(read_back), read_back, memmove};
    uint64_t start, elapsed;
    alarm(12);
    CHECK(strcmp(UDS_LIB_VERSION, "0.11.0") == 0);
    CHECK(UDSServerInit(&server) == UDS_OK);
    CHECK(UDSClientInit(&client) == UDS_OK);
    CHECK(UDSServerTpISOTpCInit(&server_tp, 0x700, 0x708, 0x7df) == UDS_OK);
    CHECK(UDSClientTpISOTpCInit(&client_tp, 0x708, 0x700, 0x7df) == UDS_OK);
    server.tp = &server_tp.hdl; server.fn = server_event;
    client.tp = &client_tp.hdl; client.fn = client_event;
    /* Allow timer granularity on a one-vCPU VM; this is not a real-time test. */
    client.p2_ms = 500;
    for (unsigned i = 0; i < sizeof(written); ++i) written[i] = (uint8_t)(i * 3 + 1);
    begin(); CHECK(UDSSendWDBI(&client, did, written, sizeof(written)) == UDS_OK); complete();
    CHECK(last_error == UDS_OK && responses == 1 && memcmp(value, written, sizeof(value)) == 0);
    begin(); CHECK(UDSSendRDBI(&client, &did, 1) == UDS_OK); complete();
    CHECK(last_error == UDS_OK && responses == 1);
    CHECK(UDSUnpackRDBIResponse(&client, &var, 1) == UDS_OK);
    CHECK(memcmp(read_back, written, sizeof(written)) == 0);
    for (unsigned direction = 0; direction < 2; ++direction)
        CHECK(counts[direction][1] >= 1 && counts[direction][2] >= 8 && counts[direction][3] >= 1);
    begin(); CHECK(UDSSendRDBI(&client, &unknown, 1) == UDS_OK); complete();
    CHECK(last_error == UDS_NRC_RequestOutOfRange && responses == 0);
    CHECK(client.recv_size == 3 && client.recv_buf[0] == 0x7f && client.recv_buf[1] == 0x22 && client.recv_buf[2] == 0x31);
    drop_requests = 1; begin(); start = micros();
    CHECK(UDSSendRDBI(&client, &did, 1) == UDS_OK); complete(); elapsed = micros() - start;
    CHECK(last_error == UDS_ERR_TIMEOUT && responses == 0 && elapsed >= 500000 && elapsed < 2000000);
    drop_requests = 0; begin(); CHECK(UDSSendRDBI(&client, &did, 1) == UDS_OK); complete();
    CHECK(last_error == UDS_OK && responses == 1);
    printf("PASS iso14229 %s isotp-c fragmented request/response (%u/%u CF) negative reply timeout recovery\n",
        UDS_LIB_VERSION, counts[0][2], counts[1][2]);
    return 0;
}
