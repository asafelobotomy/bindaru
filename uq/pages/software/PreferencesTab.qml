// The Settings tab of the Software page: bindaru's own settings. `host` is the page (Page.qml).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.uq.settings
import "logic.js" as Logic

SettingsTab {
    id: tab

    /// The page (Page.qml): its state and what it does.
    property var host

    title: "Settings"
    iconName: "configure"

    SettingsCard {
        title: "Browsing"
        iconName: "view-list-details"
        Layout.fillWidth: true

        component Choice: SettingRow {
            id: choice
            property string key
            property var names: []
            property var values: []
            settingId: "layout"
            highlight: tab.host.highlight
            Layout.fillWidth: true
            UqComboBox {
                objectName: "set-" + choice.key
                model: choice.names
                currentIndex: choice.values.indexOf(tab.host.setting(choice.key))
                onActivated: i => tab.host.setConfig(choice.key, choice.values[i])
            }
        }
        component Toggle: SwitchRow {
            id: toggle
            property string key
            settingId: "layout"
            highlight: tab.host.highlight
            value: tab.host.setting(toggle.key) === true
            onChosen: v => tab.host.setConfig(toggle.key, v)
            Layout.fillWidth: true
        }

        Choice { label: "Layout"; key: "view"; names: ["List", "Grid", "Compact"]; values: ["list", "grid", "compact"] }
        Choice { label: "Spacing"; key: "density"; names: ["Comfortable", "Compact"]; values: ["comfortable", "compact"] }
        Choice { label: "Sort by"; key: "sort"; names: ["Name", "Size", "Version", "Source", "Popularity"]; values: ["name", "size", "version", "repo", "popularity"] }
        Toggle { label: "Sort in descending order"; key: "sort_descending" }
        Choice { label: "Group by"; key: "group_by"; names: ["Nothing", "Repository", "Source (repositories or AUR)"]; values: ["none", "repo", "source"] }
        Choice { label: "Start on"; key: "start_filter"; names: ["Installed software", "Browse the Arch repositories", "Browse the AUR"]; values: ["installed", "repos", "aur"] }
        Choice { label: "Search in"; key: "search_in"; names: ["Names only", "Names and descriptions"]; values: ["name", "name-description"] }
        Toggle { label: "Show the inspector"; key: "show_inspector" }
        Toggle { label: "Show packages that were only installed as dependencies"; key: "show_dependencies" }
    }

    SettingsCard {
        title: "Removing software"
        iconName: "edit-delete"
        Layout.fillWidth: true

        SwitchRow {
            settingId: "installed"
            label: "Ask before removing"
            highlight: tab.host.highlight
            value: tab.host.setting("confirm_removals") === true
            onChosen: v => tab.host.setConfig("confirm_removals", v)
            Layout.fillWidth: true
        }
    }

    SettingsCard {
        title: "The AUR"
        iconName: "security-medium"
        help: "The Arch User Repository is made by users and isn't checked by Arch. bindaru always shows you the recipe before it builds anything from it: there is no setting to skip that."
        Layout.fillWidth: true

        SwitchRow {
            settingId: "aur"
            label: "Use the AUR"
            highlight: tab.host.highlight
            value: tab.host.setting("aur_enabled") === true
            onChosen: v => tab.host.setConfig("aur_enabled", v)
            Layout.fillWidth: true
        }
        SwitchRow {
            settingId: "aur-risky"
            label: "Show orphaned or outdated AUR packages"
            highlight: tab.host.highlight
            value: tab.host.setting("aur_show_risky") === true
            onChosen: v => tab.host.setConfig("aur_show_risky", v)
            Layout.fillWidth: true
        }
        SwitchRow {
            settingId: "aur-risky"
            label: "Show what changed when an AUR package updates"
            highlight: tab.host.highlight
            value: tab.host.setting("aur_update_diff") === true
            onChosen: v => tab.host.setConfig("aur_update_diff", v)
            Layout.fillWidth: true
        }
    }

    Outcome {
        host: tab.host
        noteKey: "config"
        Layout.fillWidth: true
    }
}
