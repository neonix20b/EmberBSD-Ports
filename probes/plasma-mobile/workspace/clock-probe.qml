// SPDX-License-Identifier: BSD-3-Clause
import QtQuick
import org.kde.plasma.clock as Clock
Item {
    id: root
    property double started: Date.now()
    property double lastSecond: -1
    property int distinctSeconds: 0
    Clock.Clock {
        trackSeconds: true
        timeZone: "UTC"
        onTimeChanged: {
            const second = Math.floor(dateTime.getTime() / 1000)
            if (second !== root.lastSecond) {
                root.lastSecond = second
                root.distinctSeconds++
            }
            if (valid && root.distinctSeconds >= 3 && Date.now() - root.started >= 1000) {
                console.log("Workspace Clock advanced across three distinct seconds")
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.error("Workspace Clock did not produce aligned second ticks")
            Qt.exit(1)
        }
    }
}
