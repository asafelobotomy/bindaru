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
        Behavior on color { ColorAnimation { duration: Theme.motionFast } }

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

    // A heading over a group of entries.
    component Section: QQC2.Label {
        font.pixelSize: Theme.smallSize * 1.15
        font.bold: true
        font.capitalization: Font.AllUppercase
        color: Theme.textMuted
        Layout.leftMargin: 10
        Layout.bottomMargin: 2
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

        Section {
            text: "On this computer"
            Layout.topMargin: 4
        }
        Entry {
            objectName: "nav-all"
            label: "Installed"
            glyph: "computer"
            count: side.store.installed.packages.length > 0 ? String(side.store.installed.packages.length) : ""
            current: side.store.page === "software" && !side.store.browsing
            onClicked: side.store.go("software", "installed")
        }

        Section {
            text: "Find new software"
            Layout.topMargin: 16
        }
        Entry {
            objectName: "nav-find-all"
            label: side.store.config.aur_enabled ? "All sources" : "Arch repositories"
            glyph: "edit-find"
            current: side.store.page === "software" && side.store.filter === "all"
            onClicked: side.store.go("software", "all")
        }
        Entry {
            objectName: "nav-repos-filter"
            label: "Arch repositories"
            glyph: "package-x-generic"
            visible: side.store.config.aur_enabled
            current: side.store.page === "software" && side.store.filter === "repos"
            onClicked: side.store.go("software", "repos")
        }
        Entry {
            objectName: "nav-aur-filter"
            label: "The AUR"
            glyph: "applications-development"
            visible: side.store.config.aur_enabled
            current: side.store.page === "software" && side.store.filter === "aur"
            onClicked: side.store.go("software", "aur")
        }

        Section {
            text: "Manage"
            Layout.topMargin: 16
        }
        Entry {
            objectName: "nav-repos"
            label: "Software sources"
            glyph: "preferences-system-network"
            count: side.store.repos.repos.filter(r => r.enabled).length > 0 ? String(side.store.repos.repos.filter(r => r.enabled).length) : ""
            current: side.store.page === "repos"
            onClicked: side.store.go("repos", "")
        }
        Entry {
            objectName: "nav-scan"
            label: "Scan with oysterAV"
            glyph: "security-high"
            current: side.store.page === "scan"
            onClicked: side.store.go("scan", "")
        }
        Entry {
            objectName: "nav-settings"
            label: "Settings"
            glyph: "preferences-system"
            current: side.store.page === "settings"
            onClicked: side.store.go("settings", "")
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
