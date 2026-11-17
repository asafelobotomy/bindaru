// Every preference, grouped. Each change is written by `bindaru config set` as you make it.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.ScrollView {
    id: page

    property var store
    contentWidth: availableWidth
    clip: true

    component Row2: RowLayout {
        property string label
        property string help: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            QQC2.Label {
                text: parent.parent.label
                color: Theme.text
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            QQC2.Label {
                visible: parent.parent.help !== ""
                text: parent.parent.help
                color: Theme.textMuted
                font.pixelSize: Theme.smallSize * 1.15
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
        RowLayout { id: slot }
    }

    component Choice: Row2 {
        id: choice
        property string key
        property var names: []
        property var values: []
        QQC2.ComboBox {
            objectName: "set-" + choice.key
            model: choice.names
            currentIndex: Math.max(0, choice.values.indexOf(page.store.config[choice.key]))
            onActivated: i => page.store.setConfig(choice.key, choice.values[i])
            implicitWidth: 200
        }
    }

    component Toggle: Row2 {
        id: toggle
        property string key
        QQC2.Switch {
            objectName: "set-" + toggle.key
            checked: page.store.config[toggle.key] === true
            onToggled: page.store.setConfig(toggle.key, checked)
        }
    }

    ColumnLayout {
        width: page.availableWidth - 32
        x: 16
        spacing: 14

        Item { implicitHeight: 2 }

        Card {
            title: "Browsing"
            Choice { label: "Layout"; key: "view"; names: ["List", "Grid", "Compact"]; values: ["list", "grid", "compact"] }
            Choice { label: "Spacing"; key: "density"; names: ["Comfortable", "Compact"]; values: ["comfortable", "compact"] }
            Choice { label: "Sort by"; key: "sort"; names: ["Name", "Size", "Version", "Source", "Popularity"]; values: ["name", "size", "version", "repo", "popularity"] }
            Toggle { label: "Sort in descending order"; key: "sort_descending" }
            Choice { label: "Group by"; key: "group_by"; names: ["Nothing", "Repository", "Source (repositories or AUR)"]; values: ["none", "repo", "source"] }
            Choice { label: "Start on"; key: "start_filter"; names: ["Installed software", "Browse the Arch repositories", "Browse the AUR"]; values: ["installed", "repos", "aur"] }
            Choice { label: "Search in"; key: "search_in"; names: ["Names only", "Names and descriptions"]; values: ["name", "name-description"] }
            Toggle { label: "Show the inspector"; help: "Details of the selected package, beside the list."; key: "show_inspector" }
            Toggle { label: "Show packages that were only installed as dependencies"; key: "show_dependencies" }
        }

        Card {
            title: "Removing software"
            Toggle { label: "Ask before removing"; help: "You always see what will be removed first when this is on."; key: "confirm_removals" }
        }

        Card {
            title: "The AUR"
            help: "The Arch User Repository is made by users and isn't checked by Arch. bindaru always shows you the recipe before it builds anything from it: there is no setting to skip that."
            Toggle { label: "Use the AUR"; key: "aur_enabled" }
            Toggle { label: "Show orphaned or outdated AUR packages"; key: "aur_show_risky" }
            Toggle { label: "Show what changed when an AUR package updates"; key: "aur_update_diff" }
        }

        Card {
            title: "oysterAV"
            help: "oysterAV is the security scanner in the uQ family. bindaru hands it the files a package installed."
            Choice { label: "Scan new installs"; key: "scan_installs"; names: ["Never", "AUR builds only", "Everything I install"]; values: ["off", "aur", "all"] }
        }

        Kirigami.InlineMessage {
            visible: page.store.configProblem !== ""
            type: Kirigami.MessageType.Error
            text: page.store.configProblem
            Layout.fillWidth: true
        }
        Item { implicitHeight: 8 }
    }
}
