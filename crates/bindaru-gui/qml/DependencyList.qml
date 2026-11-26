// The dependencies of the package in the inspector: one group at a time, so a long list doesn't
// bury the rest. `host` is the inspector (Inspector.qml).
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "logic.js" as Logic

ColumnLayout {
    id: deps

    /// The inspector (Inspector.qml): the package and the store.
    property var host

    objectName: "dependencies"

    property string tab: ""
    property bool all: false
    readonly property int shownMax: 10
    readonly property var groups: deps.host.pkg ? Logic.depGroups(deps.host.pkg, deps.host.store.installedNames) : []
    readonly property var current: {
        for (const g of groups)
            if (g.key === tab)
                return g;
        return groups.length > 0 ? groups[0] : null;
    }

    visible: groups.length > 0
    spacing: 8
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    Layout.bottomMargin: 16
    Layout.fillWidth: true

    Connections {
        target: deps.host
        function onPkgChanged() {
            if (!deps.host.pkg || deps.host.pkg.name !== deps.lastName) {
                deps.all = false;
                deps.tab = "";
            }
            deps.lastName = deps.host.pkg ? deps.host.pkg.name : "";
        }
    }
    property string lastName: ""

    QQC2.Label {
        text: "Dependencies"
        font.bold: true
        color: Theme.text
    }
    Flow {
        spacing: 6
        Layout.fillWidth: true
        Repeater {
            model: deps.groups
            Rectangle {
                id: tabPill
                required property var modelData
                readonly property bool on: deps.current !== null && deps.current.key === modelData.key
                objectName: "dep-tab-" + modelData.key
                implicitWidth: pillText.implicitWidth + 20
                implicitHeight: pillText.implicitHeight + 10
                radius: height / 2
                color: on ? Theme.accent : pillHover.hovered ? Theme.border : Theme.overlay
                Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                signal clicked
                onClicked: { deps.tab = modelData.key; deps.all = false; }
                HoverHandler { id: pillHover }
                TapHandler { onTapped: tabPill.clicked() }
                QQC2.Label {
                    id: pillText
                    anchors.centerIn: parent
                    text: tabPill.modelData.title + " · " + tabPill.modelData.entries.length
                    color: tabPill.on ? Theme.accentText : Theme.text
                    font.pixelSize: Theme.smallSize * 1.2
                }
            }
        }
    }
    QQC2.Label {
        text: deps.current ? deps.current.hint : ""
        color: Theme.textMuted
        font.pixelSize: Theme.smallSize * 1.15
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    Repeater {
        model: deps.current ? (deps.all ? deps.current.entries : deps.current.entries.slice(0, deps.shownMax)) : []
        Rectangle {
            id: dep
            required property var modelData
            objectName: "dep-row-" + modelData.name
            Layout.fillWidth: true
            implicitHeight: depRow.implicitHeight + 8
            radius: Theme.radiusControl
            color: depHover.hovered ? Theme.overlay : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.motionFast } }
            HoverHandler { id: depHover }
            TapHandler { onTapped: deps.host.store.openDependency(dep.modelData.name) }
            RowLayout {
                id: depRow
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 10
                Tile {
                    name: dep.modelData.name
                    source: deps.host.store.iconFor(dep.modelData.name)
                    size: 28
                    Layout.alignment: Qt.AlignTop
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: dep.modelData.name + (dep.modelData.constraint !== "" ? "  " + dep.modelData.constraint : "")
                        color: Theme.text
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        visible: dep.modelData.reason !== ""
                        text: dep.modelData.reason
                        color: Theme.textMuted
                        font.pixelSize: Theme.smallSize * 1.15
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                Chip {
                    text: "Installed"
                    tone: "ok"
                    visible: dep.modelData.installed
                    Layout.alignment: Qt.AlignTop
                }
            }
        }
    }
    QQC2.Button {
        objectName: "dep-more"
        visible: deps.current !== null && deps.current.entries.length > deps.shownMax
        text: deps.all ? "Show fewer" : "Show all " + (deps.current ? deps.current.entries.length : 0)
        flat: true
        onClicked: deps.all = !deps.all
    }
}
