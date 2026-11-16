import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// A titled group of rows on a raised surface.
Rectangle {
    id: card

    property string title: ""
    property string help: ""
    default property alias content: body.data

    color: Theme.surface
    radius: Theme.radius
    border.color: Theme.border
    implicitHeight: column.implicitHeight + 28
    Layout.fillWidth: true

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8
        QQC2.Label {
            visible: card.title !== ""
            text: card.title
            font.bold: true
            color: Theme.text
        }
        QQC2.Label {
            visible: card.help !== ""
            text: card.help
            wrapMode: Text.Wrap
            color: Theme.textMuted
            font.pixelSize: Theme.smallSize * 1.15
            Layout.fillWidth: true
        }
        ColumnLayout {
            id: body
            spacing: 6
            Layout.fillWidth: true
        }
    }
}
