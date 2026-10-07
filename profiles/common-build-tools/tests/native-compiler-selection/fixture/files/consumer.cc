#include <iostream>
#include <stdexcept>
#include <string>
#if __GNUC__ != 16 || __GNUC_MINOR__ != 2 || __cplusplus < 202002L
#error The actual pkgsrc C++ wrapper did not select GCC 16.2/C++20
#endif
int main() {
    try { throw std::runtime_error(std::string("selected GCC16 runtime")); }
    catch (const std::runtime_error &e) {
        if (std::string(e.what()) != "selected GCC16 runtime") return 1;
        std::cout << "PASS: native pkgsrc C++20 wrapper and exception runtime\n";
    }
}
