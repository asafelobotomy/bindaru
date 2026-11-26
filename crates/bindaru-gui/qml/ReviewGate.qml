// The AUR review gate in the inspector: what the recipe does that deserves a look, then the
// install of exactly that recipe. `host` is the inspector (Inspector.qml).
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "logic.js" as Logic

Rectangle {
    id: gate

    /// The inspector (Inspector.qml): the package and the store.
    property var host

    visible: gate.host.store.review !== null
    color: Theme.surfaceAlt
    radius: Theme.radius
    border.color: gate.host.store.review && gate.host.store.review.worst === "danger" ? Theme.error : Theme.border
    Layout.fillWidth: true
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    implicitHeight: reviewColumn.implicitHeight + 24

    ColumnLayout {
        id: reviewColumn
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        QQC2.Label {
            text: "Review before building"
            font.bold: true
            color: Theme.text
        }
        QQC2.Label {
            text: gate.host.store.review ? (gate.host.store.review.problem !== "" ? gate.host.store.review.problem : Logic.reviewHeadline(gate.host.store.review)) : ""
            wrapMode: Text.Wrap
            color: Theme.text
            Layout.fillWidth: true
        }
        Repeater {
            model: gate.host.store.review ? gate.host.store.review.findings : []
            ColumnLayout {
                required property var modelData
                spacing: 0
                Layout.fillWidth: true
                QQC2.Label {
                    text: (modelData.severity === "danger" ? "Danger" : modelData.severity === "warn" ? "Warning" : "Note") + " · line " + modelData.line + ": " + modelData.text
                    wrapMode: Text.Wrap
                    color: modelData.severity === "danger" ? Theme.error : Theme.text
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: modelData.snippet
                    font.family: Theme.fontMono
                    wrapMode: Text.WrapAnywhere
                    color: Theme.textMuted
                    Layout.fillWidth: true
                }
            }
        }
        QQC2.Label {
            visible: gate.host.store.review !== null && gate.host.store.review.problem === ""
            text: "The recipe is in ~/.cache/bindaru/build/" + (gate.host.store.review ? gate.host.store.review.name : "") + ". Installing builds it as you; only the finished package gets administrator rights."
            wrapMode: Text.Wrap
            color: Theme.textMuted
            font.pixelSize: Theme.smallSize * 1.15
            Layout.fillWidth: true
        }
        RowLayout {
            spacing: 8
            QQC2.Button {
                objectName: "accept-review"
                visible: gate.host.store.review !== null && gate.host.store.review.problem === ""
                text: "I've read it, install"
                highlighted: true
                enabled: !gate.host.store.busy
                onClicked: gate.host.store.acceptReview()
            }
            QQC2.Button {
                objectName: "dismiss-review"
                text: "Cancel"
                onClicked: gate.host.store.review = null
            }
        }
    }
}
