import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2

// A small label: a source ("AUR", "extra"), a state ("Installed") or a warning.
Rectangle {
    id: chip

    property alias text: label.text
    /// "neutral", "accent", "warn", "danger", "ok"
    property string tone: "neutral"

    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 6
    radius: height / 2
    color: tone === "accent" ? Theme.accent : tone === "warn" ? Qt.alpha(Theme.warning, 0.2) : tone === "danger" ? Qt.alpha(Theme.error, 0.2) : tone === "ok" ? Qt.alpha(Theme.success, 0.2) : Theme.overlay

    QQC2.Label {
        id: label
        anchors.centerIn: parent
        font.pixelSize: Theme.smallSize * 1.25
        color: chip.tone === "accent" ? Theme.accentText : chip.tone === "warn" ? Theme.warning : chip.tone === "danger" ? Theme.error : chip.tone === "ok" ? Theme.success : Theme.textMuted
    }
}
