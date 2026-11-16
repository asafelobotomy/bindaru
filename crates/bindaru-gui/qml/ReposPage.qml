// Repositories: switch the official optional ones, add a repository (HTTPS, signed) and remove
// the ones bindaru added. Changes go through the root helper, one password prompt each.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "logic.js" as Logic

QQC2.ScrollView {
    id: page

    property var store
    property bool adding: false
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: page.availableWidth - 32
        x: 16
        spacing: 14

        Item { implicitHeight: 2 }

        Card {
            title: "Repositories"
            help: "Packages come from the repositories that are on, in this order. After a change, bindaru refreshes the package lists; run bindleUP for a full system upgrade."

            Repeater {
                model: page.store.repos.repos
                RowLayout {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Tile {
                        name: row.modelData.name
                        size: 32
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        RowLayout {
                            spacing: 8
                            QQC2.Label {
                                text: row.modelData.name
                                color: Theme.text
                            }
                            Chip {
                                text: row.modelData.origin === "official" ? "Official" : row.modelData.origin === "added" ? "Added" : "Other"
                                tone: row.modelData.origin === "added" ? "accent" : "neutral"
                            }
                        }
                        QQC2.Label {
                            text: Logic.REPO_HELP[row.modelData.origin] + (row.modelData.servers.length > 0 ? "  " + row.modelData.servers[0] : "")
                            elide: Text.ElideRight
                            color: Theme.textMuted
                            font.pixelSize: Theme.smallSize * 1.15
                            Layout.fillWidth: true
                        }
                    }
                    QQC2.Switch {
                        objectName: "repo-switch-" + row.modelData.name
                        visible: row.modelData.origin === "official" && row.modelData.name !== "core" && row.modelData.name !== "extra"
                        checked: row.modelData.enabled
                        enabled: !page.store.busy
                        onToggled: page.store.setOfficial(row.modelData.name, checked)
                    }
                    QQC2.Button {
                        objectName: "repo-remove-" + row.modelData.name
                        visible: row.modelData.origin === "added"
                        text: "Remove"
                        enabled: !page.store.busy
                        onClicked: page.store.removeRepo(row.modelData.name)
                    }
                }
            }
            QQC2.Label {
                visible: page.store.repos.problem !== ""
                text: page.store.repos.problem
                color: Theme.error
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Card {
            title: "Add a repository"
            help: "Only HTTPS servers, and packages must be signed. If the repository has its own signing key, paste its full 40-digit fingerprint: bindaru will ask you to trust it as a separate step."

            QQC2.TextField {
                id: name
                objectName: "repo-name"
                placeholderText: "Name, for example my-repo"
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: server
                objectName: "repo-server"
                placeholderText: "Server, for example https://example.org/$repo/os/$arch"
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: key
                objectName: "repo-key"
                placeholderText: "Signing key fingerprint (optional)"
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: "Trusting a key means software signed with it installs without a warning. Only do this for a repository you trust."
                visible: key.text !== ""
                color: Theme.warning
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            QQC2.Button {
                objectName: "repo-add"
                text: "Add repository"
                highlighted: true
                enabled: !page.store.busy && name.text !== "" && server.text.indexOf("https://") === 0
                onClicked: page.store.addRepo(name.text.trim(), server.text.trim(), key.text.trim().toUpperCase())
            }
        }

        QQC2.Label {
            visible: page.store.note !== ""
            text: page.store.note
            color: page.store.noteFailed ? Theme.error : Theme.text
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Item { implicitHeight: 8 }
    }
}
