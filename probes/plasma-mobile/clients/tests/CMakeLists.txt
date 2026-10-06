cmake_minimum_required(VERSION 3.29)
project(EmberBSDPlasmaClientsProbe LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.9 REQUIRED COMPONENTS Core DBus Gui Qml)
qt_standard_project_setup()
find_package(Qt6Keychain 0.17.0 CONFIG REQUIRED)
find_package(KF6ModemManagerQt 6.26.0 CONFIG REQUIRED)
find_package(KF6NetworkManagerQt 6.26.0 CONFIG REQUIRED)
find_package(KF6BluezQt 6.26.0 CONFIG REQUIRED)
qt_add_executable(client-probe client-probe.cpp)
target_link_libraries(client-probe PRIVATE
    Qt6::Core
    Qt6::DBus
    KF6::ModemManagerQt
    Qt6Keychain::Qt6Keychain
    KF6::NetworkManagerQt
    KF6::BluezQt
)

qt_add_executable(qml-client-probe qml-client-probe.cpp)
target_link_libraries(qml-client-probe PRIVATE Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml)
