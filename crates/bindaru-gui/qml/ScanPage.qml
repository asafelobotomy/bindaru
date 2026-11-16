// Scan installed software with oysterAV.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "logic.js" as Logic

QQC2.ScrollView {
    id: page

    property var store
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: page.availableWidth - 32
        x: 16
        spacing: 14

        Item { implicitHeight: 2 }

        Card {
            title: "Scan what is installed"
            help: "oysterAV looks at the programs, libraries and settings files each package installed. Software from the AUR is the best place to start."

            RowLayout {
                spacing: 8
                QQC2.Button {
                    objectName: "scan-aur"
                    text: "Scan AUR and other outside packages"
                    highlighted: true
                    enabled: !page.store.busy
                    onClicked: page.store.scan(["--aur"], "the AUR packages")
                }
                QQC2.Button {
                    objectName: "scan-all"
                    text: "Scan everything installed"
                    enabled: !page.store.busy
                    onClicked: page.store.scan(["--all"], "everything installed")
                }
            }
            QQC2.Label {
                text: "A full scan of everything can take a while."
                color: Theme.textMuted
                font.pixelSize: Theme.smallSize * 1.15
            }
            QQC2.ProgressBar {
                visible: page.store.progress !== null
                indeterminate: true
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: page.store.progress !== null ? Logic.progressLine(page.store.progress) : page.store.note
                visible: text !== ""
                wrapMode: Text.Wrap
                color: page.store.progress === null && page.store.noteFailed ? Theme.error : Theme.text
                Layout.fillWidth: true
            }
        }

        Card {
            title: "Scan new installs automatically"
            help: "Change this in Settings. Right now: "
                  + (page.store.config.scan_installs === "off" ? "off." : page.store.config.scan_installs === "aur" ? "AUR builds only." : "everything you install.")
            QQC2.Button {
                text: "Open Settings"
                onClicked: page.store.page = "settings"
            }
        }
        Item { implicitHeight: 8 }
    }
}
