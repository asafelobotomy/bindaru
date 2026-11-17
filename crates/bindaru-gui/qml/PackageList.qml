// The main view: packages as a list, a grid of cards or a compact table; grouped by the
// setting. Selecting one opens it in the inspector.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "logic.js" as Logic

Item {
    id: view

    property var store
    readonly property string mode: store.config.view
    readonly property int rowHeight: store.config.density === "compact" ? 44 : 60

    function empty() {
        return view.store.shown.length === 0;
    }

    // What an empty list means depends on where you are: nothing installed matching your filter, or
    // a catalogue you haven't searched yet.
    readonly property string typed: store.query.trim()
    readonly property string where: store.filter === "aur" ? "the AUR" : store.filter === "repos" || !store.config.aur_enabled ? "the Arch repositories" : "the Arch repositories and the AUR"

    Kirigami.PlaceholderMessage {
        id: placeholder
        objectName: "empty"
        anchors.centerIn: parent
        visible: view.empty()
        width: Math.min(parent.width - 48, 380)
        icon.name: view.store.installed.problem !== "" && !view.store.browsing ? "dialog-error" : view.store.browsing ? "edit-find" : "computer"
        text: {
            if (!view.store.browsing)
                return view.store.installed.problem !== "" ? "Couldn't read the installed software" : view.typed !== "" ? "No installed software matches “" + view.typed + "”" : "Nothing is installed yet";
            if (view.typed.length < 2)
                return "Find software to install";
            return view.store.searching ? "Nothing matches “" + view.typed + "” in " + view.where : "Searching " + view.where + "…";
        }
        explanation: {
            if (!view.store.browsing)
                return view.store.installed.problem !== "" ? view.store.installed.problem : view.typed !== "" ? "This list only has what is on this computer." : "";
            return view.typed.length < 2 ? "Type in the search box to look in " + view.where + "." : "";
        }
        helpfulAction: view.offerSearch ? searchRepos : null
    }

    readonly property bool offerSearch: !store.browsing && typed !== "" && store.installed.problem === ""
    Kirigami.Action {
        id: searchRepos
        objectName: "search-repos"
        icon.name: "edit-find"
        text: "Search the repositories for “" + view.typed + "”"
        onTriggered: view.store.go("software", "all")
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
                    source: view.store.iconFor(row.modelData.name)
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
                    visible: row.modelData.installed && view.store.browsing
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
        cellHeight: 150
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
                            source: view.store.iconFor(cell.modelData.name)
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
                            visible: cell.modelData.installed && view.store.browsing
                        }
                    }
                }
            }
        }
    }
}
