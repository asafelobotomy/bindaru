// One package: icon tile, name and what it is, and Install or Remove.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.uq.settings
import "logic.js" as Logic

RowLayout {
    id: row

    property var host
    property var pkg
    readonly property string key: "pkg:" + row.pkg.name

    spacing: 12

    UqAppIcon {
        name: row.pkg.name
        label: row.pkg.name
        size: 32
    }
    ColumnLayout {
        spacing: 0
        Layout.fillWidth: true

        UqLabel {
            text: row.pkg.name
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        UqLabel {
            text: Logic.subtitleOf(row.pkg) + (row.pkg.installed ? " · installed" : "")
            elide: Text.ElideRight
            opacity: 0.7
            Layout.fillWidth: true
        }
    }
    QQC2.Button {
        objectName: "install-" + row.pkg.name
        text: "Install"
        icon.name: "download"
        visible: !row.pkg.installed
        enabled: !!row.host && !row.host.busy
        onClicked: row.host.install(row.pkg)
    }
    QQC2.Button {
        objectName: "remove-" + row.pkg.name
        text: "Remove"
        icon.name: "edit-delete"
        visible: row.pkg.installed
        enabled: !!row.host && !row.host.busy
        onClicked: row.host.remove(row.pkg)
    }
}
