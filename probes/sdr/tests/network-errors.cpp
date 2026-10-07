// SPDX-License-Identifier: MIT
#include <iio/iio.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <poll.h>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <thread>
#define CHECK(x) do { if (!(x)) throw std::runtime_error(#x); } while (0)
int main()
try {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(listener >= 0);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0);
    socklen_t length = sizeof(address);
    CHECK(getsockname(listener, reinterpret_cast<sockaddr *>(&address), &length) == 0);
    const std::string uri = "ip:127.0.0.1:" + std::to_string(ntohs(address.sin_port));
    iio_context_params params{};
    params.timeout_ms = 100;
    iio_context *ctx;
    CHECK(listen(listener, 1) == 0);
    bool accepted = false;
    std::thread server([&] {
        pollfd pfd{listener, POLLIN, 0};
        if (poll(&pfd, 1, 1000) > 0) {
            int peer = accept(listener, nullptr, nullptr);
            if (peer >= 0) {
                accepted = true;
                // No protocol bytes: fail by client timeout, not server EOF.
                std::this_thread::sleep_for(std::chrono::milliseconds(750));
                close(peer);
            }
        }
    });
    const auto start = std::chrono::steady_clock::now();
    ctx = iio_create_context(&params, uri.c_str());
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    int error = iio_err(ctx);
    if (!error) iio_context_destroy(ctx);
    server.join();
    close(listener);
    std::cerr << "silent result=" << error << " elapsed_ms=" << elapsed << " accepted=" << accepted << '\n';
    CHECK(accepted);
    CHECK(error == -ETIMEDOUT);
    CHECK(elapsed >= 50 && elapsed < 600);
    ctx = iio_create_context(&params, uri.c_str());
    CHECK(iio_err(ctx) == -ECONNREFUSED);
    std::cout << "PASS libiio1 network: refused connection; accepted silent server timed out in " << elapsed << " ms\n";
    return 0;
} catch (const std::exception &e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }
