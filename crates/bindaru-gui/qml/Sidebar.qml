// The left column: where you are (Software, Repositories, Scan, Settings), and on Software which
// part of the catalogue the list shows.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "logic.js" as Logic

Rectangle {
    id: side

    property var store

    implicitWidth: 224
    color: Theme.bg

    Kirigami.Separator {
        anchors.right: parent.right
        height: parent.height
    }

    component Entry: Rectangle {
        id: entry
        property string label
        property string glyph: ""
        property bool current: false
        property string count: ""
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.radius - 2
        color: current ? Theme.accent : hover.hovered ? Theme.overlay : "transparent"

        HoverHandler { id: hover }
        TapHandler { onTapped: entry.clicked() }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8
            Kirigami.Icon {
                source: entry.glyph
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
            QQC2.Label {
                text: entry.label
                color: entry.current ? Theme.accentText : Theme.text
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            QQC2.Label {
                text: entry.count
                visible: entry.count !== ""
                color: entry.current ? Theme.accentText : Theme.textMuted
                font.pixelSize: Theme.smallSize * 1.25
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 2

        RowLayout {
            spacing: 10
            Layout.bottomMargin: 12
            Tile {
                name: "bindaru"
                size: 32
            }
            QQC2.Label {
                text: "bindaru"
                font.pixelSize: Theme.headingSize
                font.bold: true
                color: Theme.text
            }
        }

        QQC2.Label {
            text: "SOFTWARE"
            font.pixelSize: Theme.smallSize * 1.15
            font.bold: true
            color: Theme.textMuted
            Layout.topMargin: 4
            Layout.leftMargin: 10
        }
        Entry {
            objectName: "nav-all"
            label: "Installed"
            glyph: "system-software-install"
            count: side.store.installed.packages.length > 0 ? String(side.store.installed.packages.length) : ""
            current: side.store.page === "software" && side.store.filter === "all" || side.store.page === "software" && side.store.filter === "installed"
            onClicked: { side.store.page = "software"; side.store.filter = "all"; }
        }
        Entry {
            objectName: "nav-repos-filter"
            label: "From repositories"
            glyph: "package-x-generic"
            current: side.store.page === "software" && side.store.filter === "repos"
            onClicked: { side.store.page = "software"; side.store.filter = "repos"; }
        }
        Entry {
            objectName: "nav-aur-filter"
            label: "From the AUR"
            glyph: "applications-development"
            visible: side.store.config.aur_enabled
            current: side.store.page === "software" && side.store.filter === "aur"
            onClicked: { side.store.page = "software"; side.store.filter = "aur"; }
        }

        QQC2.Label {
            text: "MANAGE"
            font.pixelSize: Theme.smallSize * 1.15
            font.bold: true
            color: Theme.textMuted
            Layout.topMargin: 16
            Layout.leftMargin: 10
        }
        Entry {
            objectName: "nav-repos"
            label: "Repositories"
            glyph: "preferences-system-network"
            count: side.store.repos.repos.filter(r => r.enabled).length > 0 ? String(side.store.repos.repos.filter(r => r.enabled).length) : ""
            current: side.store.page === "repos"
            onClicked: side.store.page = "repos"
        }
        Entry {
            objectName: "nav-scan"
            label: "Scan with oysterAV"
            glyph: "security-high"
            current: side.store.page === "scan"
            onClicked: side.store.page = "scan"
        }
        Entry {
            objectName: "nav-settings"
            label: "Settings"
            glyph: "preferences-system"
            current: side.store.page === "settings"
            onClicked: side.store.page = "settings"
        }

        Item { Layout.fillHeight: true }

        QQC2.Label {
            text: "System upgrades live in bindleUP."
            wrapMode: Text.Wrap
            color: Theme.textMuted
            font.pixelSize: Theme.smallSize * 1.15
            Layout.fillWidth: true
            Layout.leftMargin: 10
        }
        QQC2.Button {
            objectName: "open-bindleup"
            text: "Open bindleUP"
            flat: true
            Layout.leftMargin: 4
            onClicked: side.store.openBindleUp()
        }
    }
}
