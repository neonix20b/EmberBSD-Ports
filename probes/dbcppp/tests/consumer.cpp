// SPDX-License-Identifier: MIT
#include <dbcppp/Network.h>
#include <array>
#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unistd.h>

static void check(bool ok, const char *what)
{
    if (!ok) throw std::runtime_error(what);
}
static void near(double a, double b)
{
    check(std::fabs(a-b) < 1e-9, "physical signal mismatch");
}
int main(int argc, char **argv)
{
    alarm(15);
    try {
        check(argc == 4, "valid/malformed fixtures and temporary KCD path required");
        auto networks = dbcppp::INetwork::LoadNetworkFromFile(argv[1]);
        check(networks.size() == 1, "one parsed network");
        const auto &network = *networks.begin()->second;
        check(network.Messages_Size() == 1, "one parsed message");
        const auto &message = network.Messages_Get(0);
        check(message.Id() == 100 && message.MessageSize() == 8, "message metadata");
        check(message.Signals_Size() == 6, "six parsed signals");
        const auto &little = message.Signals_Get(0);
        const auto &big = message.Signals_Get(1);
        const auto &signed_signal = message.Signals_Get(2);
        const auto &selector = message.Signals_Get(3);
        alignas(8) std::array<unsigned char, 8> frame{0x34,0x12,0xab,0xcd,0xf6,1,42,0};
        check(little.Decode(frame.data()) == 0x1234, "little endian decode");
        check(big.Decode(frame.data()) == 0xabcd, "big endian decode");
        near(signed_signal.RawToPhys(signed_signal.Decode(frame.data())), -15.0);
        check(selector.MultiplexerIndicator() == dbcppp::ISignal::EMultiplexer::MuxSwitch, "mux switch");
        for (unsigned value : {1U, 2U}) {
            frame[5] = value;
            unsigned selected = 0;
            for (const auto &signal : message.Signals()) {
                if (signal.MultiplexerIndicator() != dbcppp::ISignal::EMultiplexer::MuxValue ||
                    signal.MultiplexerSwitchValue() != selector.Decode(frame.data())) continue;
                near(signal.RawToPhys(signal.Decode(frame.data())), value == 1 ? 85 : 125);
                check(signal.Name() == (value == 1 ? "VariantOne" : "VariantTwo"), "mux selection");
                ++selected;
            }
            check(selected == 1, "exactly one active multiplexed signal");
        }
        alignas(8) std::array<unsigned char, 8> encoded{};
        little.Encode(0x1234, encoded.data());
        big.Encode(0xabcd, encoded.data());
        signed_signal.Encode(signed_signal.PhysToRaw(-15), encoded.data());
        check(encoded[0] == 0x34 && encoded[1] == 0x12 && encoded[2] == 0xab &&
            encoded[3] == 0xcd && encoded[4] == 0xf6, "independent wire encoding");
        for (const char *bad : {"not a DBC file", "VERSION \"unterminated", "VERSION \"x\"\nNS_ :\nBS_:\nBU_: ECU\nBO_ broken"}) {
            std::istringstream input(bad);
            check(!dbcppp::INetwork::LoadDBCFromIs(input), "malformed DBC accepted");
        }
        check(dbcppp::INetwork::LoadNetworkFromFile(argv[3]).empty(), "malformed file accepted");
        { std::ofstream unsupported(argv[2]); unsupported << "<NetworkDefinition/>"; }
        bool refused = false;
        try { (void)dbcppp::INetwork::LoadNetworkFromFile(argv[2]); }
        catch (const std::runtime_error &) { refused = true; }
        unlink(argv[2]);
        check(refused, "KCD must fail explicitly");
        std::cout << "PASS dbcppp DBC little/big endian signed/scaled encode/decode multiplexing malformed input KCD rejection\n";
    } catch (const std::exception &e) {
        std::cerr << e.what() << '\n'; return 1;
    }
}
