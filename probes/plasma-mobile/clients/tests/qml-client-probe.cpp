// SPDX-License-Identifier: BSD-2-Clause
// Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
#include <QGuiApplication>
#include <QDebug>
#include <QQmlComponent>
#include <QQmlEngine>
#include <memory>
#include "system-bus-preflight.h"

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (!requireInactiveSystemServices()) {
        return 2;
    }
    QQmlEngine engine;
    for (const auto *module : {"org.kde.networkmanager", "org.kde.bluezqt", "org.kde.plasma.networkmanagement", "org.kde.plasma.networkmanagement.cellular"}) {
        QQmlComponent component(&engine);
        const QByteArray source = QByteArray("import QtQml\nimport ") + module + "\nQtObject {}\n";
        component.setData(source, QUrl());
        std::unique_ptr<QObject> object(component.create());
        if (!object) {
            qCritical() << module << component.errors();
            return 1;
        }
        qInfo() << "Loaded real QML module:" << module;
    }
    return 0;
}
