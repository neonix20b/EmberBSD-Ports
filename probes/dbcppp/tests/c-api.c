/* SPDX-License-Identifier: MIT */
#include <dbcppp/CApi.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
int main(int argc, char **argv)
{
    const dbcppp_Network *network;
    const dbcppp_Message *message;
    const dbcppp_Signal *signal;
    _Alignas(8) uint8_t frame[8] = {0x34,0x12,0xab,0xcd,0xf6,1,42,0};
    int ok;
    alarm(15);
    if (argc != 2) return 1;
    network = dbcppp_NetworkLoadDBCFromFile(argv[1]);
    if (!network) return 1;
    ok = dbcppp_NetworkMessages_Size(network) == 1;
    if (ok) {
        message = dbcppp_NetworkMessages_Get(network, 0);
        ok = dbcppp_MessageSignals_Size(message) == 6;
        if (ok) {
            signal = dbcppp_MessageSignals_Get(message, 0);
            ok = dbcppp_SignalDecode(signal, frame) == 0x1234;
        }
    }
    dbcppp_NetworkFree(network);
    if (!ok) return 1;
    puts("PASS dbcppp installed C API");
    return 0;
}
