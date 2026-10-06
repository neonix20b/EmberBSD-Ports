// SPDX-License-Identifier: BSD-3-Clause
import QtQuick
import org.kde.plasma.clock as Clock
import org.kde.taskmanager as Tasks
import org.kde.notificationmanager as Notifications
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.private.battery as Battery
import org.kde.plasma.workspace.keyboardlayout as Keyboard
import org.kde.plasma.workspace.components as Workspace
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.private.containmentlayoutmanager as Layouts
import org.kde.plasma.private.shell as Shell
import org.kde.plasma.private.systemtray as Tray
import org.kde.plasma.wallpapers.image as Wallpaper

Item {
    Tasks.TasksModel { id: tasks }
    Notifications.Notifications { id: notifications }
    Battery.BatteryControlModel { id: batteries }
    Keyboard.KeyboardLayout { id: keyboard }

    Component.onCompleted: {
        Qt.callLater(() => {
            console.log("Workspace QML imports and model constructors succeeded",
                        "tasks", tasks.count,
                        "notifications", notifications.count,
                        "batteries present", batteries.hasBatteries,
                        "keyboard layouts", keyboard.layoutsList.length)
            Qt.quit()
        })
    }
}
