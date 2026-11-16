// The main view: packages as a list, a grid of cards or a compact table; grouped by the
// setting. Selecting one opens it in the inspector.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "logic.js" as Logic

Item {
    id: view

    property var store
    readonly property string mode: store.config.view
    readonly property int rowHeight: store.config.density === "compact" ? 44 : 60

    function empty() {
        return view.store.shown.length === 0;
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: view.empty()
        spacing: 6
        width: Math.min(parent.width - 48, 360)
        QQC2.Label {
            text: view.store.installed.problem !== "" ? "Couldn't read the installed software" : view.store.query.trim() !== "" ? "Nothing matches “" + view.store.query.trim() + "”" : "Nothing here yet"
            font.bold: true
            color: Theme.text
            Layout.alignment: Qt.AlignHCenter
        }
        QQC2.Label {
            text: view.store.installed.problem !== "" ? view.store.installed.problem : "Search above to find software to install."
            wrapMode: Text.Wrap
            color: Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
    }

    // ---- list and compact
    ListView {
        id: list
        objectName: "list"
        anchors.fill: parent
        visible: view.mode !== "grid" && !view.empty()
        model: view.store.shown
        clip: true
        spacing: view.mode === "compact" ? 0 : 2
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
        section.property: view.store.config.group_by === "none" ? "" : "section"
        section.delegate: QQC2.Label {
            required property string section
            text: section
            font.bold: true
            color: Theme.textMuted
            leftPadding: 16
            topPadding: 14
            bottomPadding: 4
        }
        delegate: Rectangle {
            id: row

            required property var modelData
            readonly property bool current: view.store.selected === modelData.name

            width: list.width
            height: view.mode === "compact" ? 34 : view.rowHeight
            color: current ? Qt.alpha(Theme.accent, 0.22) : rowHover.hovered ? Theme.overlay : "transparent"
            radius: Theme.radius - 2

            HoverHandler { id: rowHover }
            TapHandler { onTapped: view.store.select(row.modelData.name) }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12
                Tile {
                    name: row.modelData.name
                    size: view.mode === "compact" ? 22 : 36
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: row.modelData.name
                        elide: Text.ElideRight
                        color: Theme.text
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        visible: view.mode !== "compact"
                        text: row.modelData.description
                        elide: Text.ElideRight
                        color: Theme.textMuted
                        font.pixelSize: Theme.smallSize * 1.15
                        Layout.fillWidth: true
                    }
                }
                QQC2.Label {
                    text: row.modelData.version
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    font.pixelSize: Theme.smallSize * 1.15
                    Layout.preferredWidth: 110
                }
                QQC2.Label {
                    visible: view.mode === "compact"
                    text: Logic.sizeText(row.modelData.size)
                    color: Theme.textMuted
                    font.pixelSize: Theme.smallSize * 1.15
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 70
                }
                Chip {
                    text: Logic.sourceOf(row.modelData)
                    tone: row.modelData.aur ? "warn" : "neutral"
                }
                Chip {
                    text: "Installed"
                    tone: "ok"
                    visible: row.modelData.installed && view.store.query.trim() !== ""
                }
            }
        }
    }

    // ---- grid
    GridView {
        id: grid
        objectName: "grid"
        anchors.fill: parent
        anchors.margins: 8
        visible: view.mode === "grid" && !view.empty()
        model: view.store.shown
        clip: true
        cellWidth: Math.max(180, Math.floor(width / Math.max(1, Math.floor(width / 210))))
        cellHeight: 132
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
        delegate: Item {
            id: cell

            required property var modelData
            readonly property bool current: view.store.selected === modelData.name

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 5
                radius: Theme.radius
                color: cell.current ? Qt.alpha(Theme.accent, 0.22) : Theme.surface
                border.color: cell.current ? Theme.accent : Theme.border
                border.width: 1

                HoverHandler { id: cellHover }
                TapHandler { onTapped: view.store.select(cell.modelData.name) }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4
                    RowLayout {
                        spacing: 10
                        Tile {
                            name: cell.modelData.name
                            size: 40
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: cell.modelData.name
                                elide: Text.ElideRight
                                font.bold: true
                                color: Theme.text
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: cell.modelData.version
                                elide: Text.ElideRight
                                color: Theme.textMuted
                                font.pixelSize: Theme.smallSize * 1.15
                                Layout.fillWidth: true
                            }
                        }
                    }
                    QQC2.Label {
                        text: cell.modelData.description
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.textMuted
                        font.pixelSize: Theme.smallSize * 1.15
                        Layout.fillWidth: true
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: 6
                        Chip {
                            text: Logic.sourceOf(cell.modelData)
                            tone: cell.modelData.aur ? "warn" : "neutral"
                        }
                        Chip {
                            text: "Installed"
                            tone: "ok"
                            visible: cell.modelData.installed && view.store.query.trim() !== ""
                        }
                    }
                }
            }
        }
    }
}
