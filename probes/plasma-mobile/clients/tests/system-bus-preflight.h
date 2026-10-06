// SPDX-License-Identifier: BSD-2-Clause
// Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
#ifndef EMBERBSD_SYSTEM_BUS_PREFLIGHT_H
#define EMBERBSD_SYSTEM_BUS_PREFLIGHT_H

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDebug>
#include <QStringList>

inline bool requireInactiveSystemServices()
{
    const auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        qCritical() << "System D-Bus preflight rejected: bus is unavailable.";
        return false;
    }
    QStringList owned;
    QStringList activatable;
    for (const auto *method : {"ListNames", "ListActivatableNames"}) {
        auto message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
            QString::fromLatin1(method));
        message.setAutoStartService(false);
        const QDBusReply<QStringList> reply = bus.call(message, QDBus::Block, 5000);
        if (!reply.isValid()) {
            qCritical().noquote() << "System D-Bus preflight rejected: query failed:" << method << reply.error().name();
            return false;
        }
        if (qstrcmp(method, "ListNames") == 0) {
            owned = reply.value();
        } else {
            activatable = reply.value();
        }
    }
    for (const auto *name : {"org.freedesktop.ModemManager1", "org.freedesktop.NetworkManager", "org.bluez"}) {
        const auto service = QString::fromLatin1(name);
        if (owned.contains(service)) {
            qCritical().noquote() << "System D-Bus preflight rejected: service is owned:" << service;
            return false;
        }
        if (activatable.contains(service)) {
            qCritical().noquote() << "System D-Bus preflight rejected: service is activatable:" << service;
            return false;
        }
    }
    qInfo() << "System D-Bus preflight passed: no owned or activatable client services.";
    return true;
}
#endif
