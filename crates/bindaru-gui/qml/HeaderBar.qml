// The top bar: the title, the search box (searches as you type), sort and view controls, and the
// inspector switch. The page it sits on decides which controls apply.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts

Rectangle {
    id: bar

    property var store
    readonly property var sortNames: ["Name", "Size", "Version", "Source", "Popularity"]
    readonly property var sortKeys: ["name", "size", "version", "repo", "popularity"]
    readonly property bool onSoftware: store.page === "software"

    implicitHeight: 56
    color: Theme.surface

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        QQC2.Label {
            text: bar.store.page === "software" ? "Software" : bar.store.page === "repos" ? "Repositories" : bar.store.page === "scan" ? "Scan with oysterAV" : "Settings"
            font.pixelSize: Theme.headingSize
            font.bold: true
            color: Theme.text
            Layout.preferredWidth: 180
        }

        QQC2.TextField {
            id: search
            objectName: "search"
            visible: bar.onSoftware
            placeholderText: bar.store.config.search_in === "name" ? "Search by name" : "Search names and descriptions"
            text: bar.store.query
            selectByMouse: true
            Layout.fillWidth: true
            Layout.maximumWidth: 520
            onTextEdited: debounce.restart()
            Timer {
                id: debounce
                interval: 250
                onTriggered: bar.store.search(search.text)
            }
        }
        Item {
            Layout.fillWidth: true
            visible: !bar.onSoftware
        }

        QQC2.ComboBox {
            id: sortBox
            objectName: "sort"
            visible: bar.onSoftware
            model: bar.sortNames
            currentIndex: Math.max(0, bar.sortKeys.indexOf(bar.store.config.sort))
            onActivated: i => bar.store.setConfig("sort", bar.sortKeys[i])
            implicitWidth: 130
        }
        QQC2.ToolButton {
            objectName: "sort-direction"
            visible: bar.onSoftware
            text: bar.store.config.sort_descending ? "↓" : "↑"
            onClicked: bar.store.setConfig("sort_descending", !bar.store.config.sort_descending)
            QQC2.ToolTip.text: bar.store.config.sort_descending ? "Descending" : "Ascending"
            QQC2.ToolTip.visible: hovered
        }
        Row {
            visible: bar.onSoftware
            spacing: 0
            Repeater {
                model: [{ key: "list", text: "☰" }, { key: "grid", text: "▦" }, { key: "compact", text: "≣" }]
                QQC2.ToolButton {
                    required property var modelData
                    objectName: "view-" + modelData.key
                    text: modelData.text
                    checkable: true
                    checked: bar.store.config.view === modelData.key
                    onClicked: bar.store.setConfig("view", modelData.key)
                }
            }
        }
        QQC2.ToolButton {
            objectName: "toggle-inspector"
            visible: bar.onSoftware
            text: "▐"
            checkable: true
            checked: bar.store.config.show_inspector
            onClicked: bar.store.setConfig("show_inspector", !bar.store.config.show_inspector)
            QQC2.ToolTip.text: "Inspector"
            QQC2.ToolTip.visible: hovered
        }
    }
}
