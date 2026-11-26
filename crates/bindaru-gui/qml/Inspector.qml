// The right column: the selected package in detail, what you can do with it, and the steps of
// whatever is running. AUR packages show their trust signals and the review before any install.
import QtQuick
import org.bindaru.app
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "logic.js" as Logic

Rectangle {
    id: ins

    property var store
    readonly property var pkg: store.details !== null ? store.details.pkg : store.selectedPackage
    readonly property var aur: store.details !== null ? store.details.aur : null

    implicitWidth: 340
    color: Theme.surface

    Rectangle {
        width: 1
        height: parent.height
        color: Theme.border
    }

    QQC2.Label {
        anchors.centerIn: parent
        visible: ins.pkg === null
        text: "Select software to see its details"
        color: Theme.textMuted
        width: parent.width - 48
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }

    QQC2.ScrollView {
        anchors.fill: parent
        anchors.leftMargin: 1
        visible: ins.pkg !== null
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: ins.width - 1
            spacing: 12

            RowLayout {
                spacing: 12
                Layout.margins: 16
                Layout.bottomMargin: 0
                Tile {
                    name: ins.pkg ? ins.pkg.name : ""
                    source: ins.pkg ? ins.store.iconFor(ins.pkg.name) : ""
                    size: 56
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: ins.pkg ? ins.pkg.name : ""
                        font.pixelSize: Theme.headingSize
                        font.bold: true
                        color: Theme.text
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 6
                        QQC2.Label {
                            text: ins.pkg ? ins.pkg.version : ""
                            color: Theme.textMuted
                        }
                        Chip {
                            text: ins.pkg ? Logic.sourceOf(ins.pkg) : ""
                            tone: ins.pkg && ins.pkg.aur ? "warn" : "neutral"
                        }
                        Chip {
                            text: "Installed"
                            tone: "ok"
                            visible: ins.pkg !== null && ins.pkg.installed
                        }
                    }
                }
            }

            QQC2.Label {
                text: ins.pkg ? ins.pkg.description : ""
                wrapMode: Text.Wrap
                color: Theme.text
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
            }

            // ---- actions
            RowLayout {
                spacing: 8
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                QQC2.Button {
                    objectName: "act-install"
                    visible: ins.pkg !== null && !ins.pkg.installed
                    text: ins.pkg && ins.pkg.aur ? "Review and install…" : "Install"
                    highlighted: true
                    enabled: !ins.store.busy
                    onClicked: ins.pkg.aur ? ins.store.reviewAur(ins.pkg) : ins.store.ask("install", ins.pkg)
                }
                QQC2.Button {
                    objectName: "act-remove"
                    visible: ins.pkg !== null && ins.pkg.installed
                    text: "Remove"
                    enabled: !ins.store.busy
                    onClicked: ins.store.ask("remove", ins.pkg)
                }
                QQC2.Button {
                    objectName: "act-scan"
                    visible: ins.pkg !== null && ins.pkg.installed
                    text: "Scan with oysterAV"
                    enabled: !ins.store.busy
                    onClicked: ins.store.scan([ins.pkg.name], ins.pkg.name)
                }
            }

            // ---- confirmation of an install or removal
            Rectangle {
                visible: ins.store.plan !== null
                color: Theme.surfaceAlt
                radius: Theme.radius
                border.color: Theme.border
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                implicitHeight: planColumn.implicitHeight + 24

                ColumnLayout {
                    id: planColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    QQC2.Label {
                        text: ins.store.plan ? (ins.store.plan.action === "remove" ? "This will remove" : "This will install") : ""
                        font.bold: true
                        color: Theme.text
                    }
                    Repeater {
                        model: ins.store.plan && ins.store.plan.doc && ins.store.plan.doc.changes ? ins.store.plan.doc.changes.slice(0, 20) : []
                        QQC2.Label {
                            required property var modelData
                            text: modelData.label + (modelData.detail ? " · " + modelData.detail : "")
                            wrapMode: Text.Wrap
                            color: Theme.textMuted
                            Layout.fillWidth: true
                        }
                    }
                    RowLayout {
                        spacing: 8
                        QQC2.Button {
                            objectName: "confirm-plan"
                            text: ins.store.plan && ins.store.plan.action === "remove" ? "Remove" : "Install"
                            highlighted: true
                            onClicked: ins.store.confirmPlan()
                        }
                        QQC2.Button {
                            text: "Cancel"
                            onClicked: ins.store.plan = null
                        }
                    }
                }
            }

            // ---- the AUR review gate
            ReviewGate {
                host: ins
            }

            // ---- progress and what happened
            ColumnLayout {
                visible: ins.store.progress !== null || ins.store.note !== ""
                spacing: 6
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.fillWidth: true
                QQC2.ProgressBar {
                    visible: ins.store.progress !== null
                    indeterminate: true
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: ins.store.progress !== null ? Logic.progressLine(ins.store.progress) : ins.store.note
                    wrapMode: Text.Wrap
                    color: ins.store.progress === null && ins.store.noteFailed ? Theme.error : Theme.text
                    Layout.fillWidth: true
                }
                QQC2.Button {
                    objectName: "failure-open-bindleup"
                    visible: ins.store.progress === null && ins.store.noteNeedsUpgrade
                    text: "Open bindleUP"
                    icon.name: "system-software-update"
                    onClicked: ins.store.openBindleUp()
                }
            }

            // ---- AUR trust signals
            ColumnLayout {
                visible: ins.aur !== null
                spacing: 4
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.fillWidth: true
                QQC2.Label {
                    text: "From the AUR"
                    font.bold: true
                    color: Theme.text
                }
                QQC2.Label {
                    text: ins.aur ? (ins.aur.maintainer !== "" ? "Maintained by " + ins.aur.maintainer : "Nobody maintains this package") + " · " + ins.aur.votes + " votes · popularity " + ins.aur.popularity.toFixed(2) : ""
                    wrapMode: Text.Wrap
                    color: Theme.textMuted
                    Layout.fillWidth: true
                }
                Repeater {
                    model: ins.aur ? ins.aur.flags : []
                    QQC2.Label {
                        required property var modelData
                        text: "⚠ " + modelData.text
                        wrapMode: Text.Wrap
                        color: Theme.warning
                        Layout.fillWidth: true
                    }
                }
            }

            // ---- facts
            GridLayout {
                columns: 2
                columnSpacing: 12
                rowSpacing: 6
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.fillWidth: true

                Repeater {
                    model: ins.pkg ? [
                        ["Source", Logic.sourceOf(ins.pkg)],
                        ["Download", ins.pkg.downloadSize || ""],
                        ["Installed size", ins.pkg.installedSize || Logic.sizeText(ins.pkg.size)],
                        ["Licence", ins.pkg.licenses ? ins.pkg.licenses.join(", ") : ""],
                        ["Website", ins.pkg.url || ""],
                        ["Provides", ins.pkg.provides ? ins.pkg.provides.join(", ") : ""],
                        ["Conflicts with", ins.pkg.conflicts ? ins.pkg.conflicts.join(", ") : ""]
                    ].filter(r => r[1] !== "") : []

                    RowLayout {
                        required property var modelData
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: 12
                        QQC2.Label {
                            text: modelData[0]
                            color: Theme.textMuted
                            Layout.preferredWidth: 100
                            Layout.alignment: Qt.AlignTop
                        }
                        QQC2.Label {
                            text: modelData[1]
                            wrapMode: Text.Wrap
                            color: Theme.text
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ---- dependencies: one group at a time, so a long list doesn't bury the rest
            DependencyList {
                host: ins
            }
        }
    }
}
