// The window's layout: header on top, then sidebar, main view and inspector. Takes a Store, so
// tests can drive it with a fake backend.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts

QQC2.Pane {
    id: view

    property var store

    padding: 0
    background: Rectangle { color: Theme.bg }
    // The controls draw from this palette, so uQ's colours reach every button, field and switch.
    palette {
        window: Theme.bg
        windowText: Theme.text
        base: Theme.surfaceAlt
        alternateBase: Theme.surface
        text: Theme.text
        button: Theme.overlay
        buttonText: Theme.text
        highlight: Theme.accent
        highlightedText: Theme.accentText
        placeholderText: Theme.textMuted
        mid: Theme.border
        dark: Theme.border
        light: Theme.overlay
        toolTipBase: Theme.overlay
        toolTipText: Theme.text
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        HeaderBar {
            store: view.store
            Layout.fillWidth: true
        }
        RowLayout {
            spacing: 0
            Layout.fillWidth: true
            Layout.fillHeight: true

            Sidebar {
                store: view.store
                Layout.fillHeight: true
            }
            StackLayout {
                currentIndex: ["software", "repos", "scan", "settings"].indexOf(view.store.page)
                Layout.fillWidth: true
                Layout.fillHeight: true

                PackageList { store: view.store }
                ReposPage { store: view.store }
                ScanPage { store: view.store }
                SettingsPage { store: view.store }
            }
            Inspector {
                store: view.store
                visible: view.store.page === "software" && view.store.config.show_inspector
                Layout.fillHeight: true
            }
        }
    }
}
