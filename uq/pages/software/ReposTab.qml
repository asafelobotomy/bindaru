// The Repositories tab of the Software page: the repositories that are on, in order, and adding
// or removing one. `host` is the page (Page.qml).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.uq.settings
import "logic.js" as Logic

SettingsTab {
    id: tab

    /// The page (Page.qml): its state and what it does.
    property var host

    title: "Repositories"
    iconName: "network-server"

    SettingsCard {
        title: "Repositories"
        iconName: "network-server"
        help: "Packages come from the repositories that are on, in this order. After a change bindaru refreshes the package lists; run bindleUP for a full system upgrade."
        wide: true
        Layout.fillWidth: true

        ErrorCard {
            title: "Couldn't read the repositories"
            detail: tab.host.reposInfo ? tab.host.reposInfo.problem : ""
            visible: tab.host.reposInfo !== null && tab.host.reposInfo.problem !== ""
            Layout.fillWidth: true
        }
        Repeater {
            model: tab.host.reposInfo !== null ? tab.host.reposInfo.repos : []

            SettingRow {
                id: repoRow

                required property var modelData

                settingId: "repositories"
                label: repoRow.modelData.name + " — " + repoRow.modelData.where
                highlight: tab.host.highlight
                Layout.fillWidth: true

                QQC2.Switch {
                    objectName: "repo-switch-" + repoRow.modelData.name
                    visible: repoRow.modelData.switchable
                    checked: repoRow.modelData.enabled
                    enabled: !tab.host.busy
                    onToggled: tab.host.switchRepo(repoRow.modelData.name, checked)
                }
                QQC2.Button {
                    objectName: "repo-remove-" + repoRow.modelData.name
                    visible: repoRow.modelData.removable
                    text: "Remove"
                    icon.name: "list-remove"
                    enabled: !tab.host.busy
                    onClicked: tab.host.removeRepo(repoRow.modelData.name)
                }
            }
        }
        Outcome {
            host: tab.host
            noteKey: "repos"
            Layout.fillWidth: true
        }
    }

    SettingsCard {
        title: "Add a repository"
        iconName: "list-add"
        help: "Only HTTPS servers, and packages must be signed. If the repository has its own signing key, paste its full 40-digit fingerprint: bindaru trusts it as a separate step."
        wide: true
        Layout.fillWidth: true

        SettingRow {
            label: "Name"
            Layout.fillWidth: true
            QQC2.TextField {
                id: repoName
                objectName: "repo-name"
                placeholderText: "my-repo"
                implicitWidth: 260
                enabled: !tab.host.busy
            }
        }
        SettingRow {
            label: "Server"
            Layout.fillWidth: true
            QQC2.TextField {
                id: repoServer
                objectName: "repo-server"
                placeholderText: "https://example.org/$repo/os/$arch"
                implicitWidth: 260
                enabled: !tab.host.busy
            }
        }
        SettingRow {
            label: "Signing key (optional)"
            Layout.fillWidth: true
            QQC2.TextField {
                id: repoKey
                objectName: "repo-key"
                placeholderText: "40-digit fingerprint"
                implicitWidth: 260
                enabled: !tab.host.busy
            }
            QQC2.Button {
                objectName: "repo-add"
                text: "Add repository"
                icon.name: "list-add"
                enabled: !tab.host.busy && repoName.text.trim() !== "" && repoServer.text.trim() !== ""
                onClicked: tab.host.addRepo(repoName.text, repoServer.text, repoKey.text)
            }
        }
        Outcome {
            host: tab.host
            noteKey: "repo-add"
            Layout.fillWidth: true
        }
    }

    ProgressCard {
        host: tab.host
        Layout.fillWidth: true
    }
}
