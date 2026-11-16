// The "Working" card: a bar while a streamed command runs, then its last line in plain words.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.uq.settings
import "logic.js" as Logic

SettingsCard {
    id: card

    /// The page (Page.qml): it holds the progress and which command is streaming.
    property var host

    title: card.host.progress !== null ? "Working" : ""
    iconName: "view-refresh"
    visible: card.host.progress !== null
    wide: true

    QQC2.ProgressBar {
        visible: card.host.streaming
        indeterminate: true
        Layout.fillWidth: true
    }
    UqLabel {
        text: card.host.progress !== null ? Logic.progressLine(card.host.progress) : ""
        wrapMode: Text.Wrap
        color: card.host.progress !== null && card.host.progress.failed !== "" ? card.host.errorColor() : card.host.textColor()
        Layout.fillWidth: true
    }
}
