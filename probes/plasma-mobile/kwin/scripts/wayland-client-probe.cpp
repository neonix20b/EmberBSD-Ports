/* SPDX-License-Identifier: MIT */
#include <QApplication>
#include <QFile>
#include <QLabel>
#include <QLineEdit>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (app.arguments().size() != 2 || QGuiApplication::platformName() != QStringLiteral("wayland")) {
        return 2;
    }
    const QString receiptPath = app.arguments().at(1);
    QWidget window;
    window.setWindowTitle(QStringLiteral("KWin native Wayland input contract"));
    window.resize(500, 220);
    window.setStyleSheet(QStringLiteral("QWidget { background: #18242f; color: #f2f5fa; font-size: 22px; } QLineEdit { background: #28566f; padding: 16px; }"));
    QVBoxLayout layout(&window);
    QLabel label(QStringLiteral("Native Qt Wayland client"));
    QLineEdit input;
    input.setPlaceholderText(QStringLiteral("Enter emberbsd through the compositor"));
    layout.addWidget(&label);
    layout.addWidget(&input);
    QObject::connect(&input, &QLineEdit::textChanged, &app, [&](const QString &text) {
        if (text != QStringLiteral("emberbsd")) {
            return;
        }
        QFile receipt(receiptPath);
        if (!receipt.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            app.exit(3);
            return;
        }
        if (receipt.write("platform=wayland\ntext=emberbsd\n") != 31) {
            app.exit(4);
            return;
        }
        receipt.close();
        QTimer::singleShot(3000, &app, [&] { app.exit(0); });
    });
    QTimer::singleShot(30000, &app, [&] { app.exit(5); });
    window.show();
    input.setFocus();
    return app.exec();
}
