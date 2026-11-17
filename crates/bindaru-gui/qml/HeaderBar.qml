// The top bar: the title, the search box (searches as you type), sort and view controls, and the
// inspector switch. The page it sits on decides which controls apply.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: bar

    property var store
    readonly property var sortNames: ["Name", "Size", "Version", "Source", "Popularity"]
    readonly property var sortKeys: ["name", "size", "version", "repo", "popularity"]
    readonly property bool onSoftware: store.page === "software"

    function title() {
        const s = store;
        if (s.page === "repos")
            return "Software sources";
        if (s.page === "scan")
            return "Scan with oysterAV";
        if (s.page === "settings")
            return "Settings";
        return s.filter === "installed" ? "Installed" : s.filter === "aur" ? "The AUR" : s.filter === "repos" || !s.config.aur_enabled ? "Arch repositories" : "Find software";
    }
    function placeholder() {
        const s = store;
        if (!s.browsing)
            return "Filter your installed software";
        const where = s.filter === "aur" ? "the AUR" : s.filter === "repos" || !s.config.aur_enabled ? "the Arch repositories" : "the repositories and the AUR";
        return "Search " + where;
    }

    implicitHeight: 56
    color: Theme.surface

    Kirigami.Separator {
        anchors.bottom: parent.bottom
        width: parent.width
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        Kirigami.Heading {
            level: 2
            text: bar.title()
            color: Theme.text
            Layout.preferredWidth: 200
        }

        Kirigami.SearchField {
            id: search
            objectName: "search"
            visible: bar.onSoftware
            placeholderText: bar.placeholder()
            text: bar.store.query
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
            icon.name: bar.store.config.sort_descending ? "view-sort-descending" : "view-sort-ascending"
            display: QQC2.AbstractButton.IconOnly
            onClicked: bar.store.setConfig("sort_descending", !bar.store.config.sort_descending)
            QQC2.ToolTip.text: bar.store.config.sort_descending ? "Descending" : "Ascending"
            QQC2.ToolTip.visible: hovered
        }
        Row {
            visible: bar.onSoftware
            spacing: 0
            Repeater {
                model: [{ key: "list", icon: "view-list-details" }, { key: "grid", icon: "view-grid" }, { key: "compact", icon: "view-list-text" }]
                QQC2.ToolButton {
                    required property var modelData
                    objectName: "view-" + modelData.key
                    icon.name: modelData.icon
                    display: QQC2.AbstractButton.IconOnly
                    checkable: true
                    checked: bar.store.config.view === modelData.key
                    onClicked: bar.store.setConfig("view", modelData.key)
                }
            }
        }
        QQC2.ToolButton {
            objectName: "toggle-inspector"
            visible: bar.onSoftware
            icon.name: "view-right-new"
            display: QQC2.AbstractButton.IconOnly
            checkable: true
            checked: bar.store.config.show_inspector
            onClicked: bar.store.setConfig("show_inspector", !bar.store.config.show_inspector)
            QQC2.ToolTip.text: "Inspector"
            QQC2.ToolTip.visible: hovered
        }
    }
}
