// SPDX-License-Identifier: BSD-2-Clause
// Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <ModemManagerQt/Manager>
#include <NetworkManagerQt/Manager>
#include <NetworkManagerQt/Utils>
#include <BluezQt/Manager>
#include <BluezQt/InitManagerJob>
#include <qt6keychain/keychain.h>
#include <time.h>
#include "system-bus-preflight.h"

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (!requireInactiveSystemServices()) {
        return 2;
    }
    if (!ModemManager::modemDevices().isEmpty() || !NetworkManager::networkInterfaces().isEmpty()) {
        qCritical() << "Unexpected devices without service owners";
        return 3;
    }
    BluezQt::Manager bluetooth;
    auto *bluetoothInit = bluetooth.init();
    bluetoothInit->exec();
    if (bluetoothInit->error() || !bluetooth.isInitialized() || bluetooth.isOperational()
        || !bluetooth.adapters().isEmpty() || !bluetooth.devices().isEmpty()) {
        qCritical() << "Unexpected BluezQt state without a service owner";
        return 6;
    }
#ifdef CLOCK_BOOTTIME
    constexpr clockid_t clockId = CLOCK_BOOTTIME;
#else
    constexpr clockid_t clockId = CLOCK_MONOTONIC;
#endif
    timespec now{};
    if (clock_gettime(clockId, &now) != 0) {
        qCritical() << "clock_gettime failed";
        return 4;
    }
    const qint64 elapsed = qint64(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
    const auto converted = NetworkManager::clockBootTimeToDateTime(elapsed);
    const qint64 difference = converted.msecsTo(QDateTime::currentDateTime());
    if (!converted.isValid() || difference < -1000 || difference > 1000) {
        qCritical() << "Clock conversion differs by" << difference << "ms";
        return 5;
    }
    qInfo() << "QtKeychain backend available:" << QKeychain::isAvailable();
    qInfo() << "Real Qt D-Bus clients: no service owners, no devices; clock conversion passed.";
    return 0;
}
