// SPDX-License-Identifier: BSD-2-Clause
// Local EmberBSD QML import/constructor check, prepared with AI assistance.
import QtQuick
import QtQuick.Controls as Controls
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.private.nanoshell as Nano
import org.kde.plasma.private.batterymonitor as Battery
import org.kde.plasma.private.volume as Volume

Window {
    width: 240
    height: 240
    visible: true

    Column {
        anchors.centerIn: parent
        PlasmaComponents.Button { text: qsTr("EmberBSD") }
        Controls.Button { text: qsTr("Breeze") }
    }
    Nano.FullScreenOverlay { visible: false }
    Battery.PowerProfilesControl {}
    Volume.PercentValidator {}

    Timer {
        interval: 250
        running: true
        onTriggered: {
            console.log("PASS: Plasma, Nano, battery, volume and Breeze QML constructors")
            Qt.quit()
        }
    }
}
