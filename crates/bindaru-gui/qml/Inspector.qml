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
            Rectangle {
                visible: ins.store.review !== null
                color: Theme.surfaceAlt
                radius: Theme.radius
                border.color: ins.store.review && ins.store.review.worst === "danger" ? Theme.error : Theme.border
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                implicitHeight: reviewColumn.implicitHeight + 24

                ColumnLayout {
                    id: reviewColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    QQC2.Label {
                        text: "Review before building"
                        font.bold: true
                        color: Theme.text
                    }
                    QQC2.Label {
                        text: ins.store.review ? (ins.store.review.problem !== "" ? ins.store.review.problem : Logic.reviewHeadline(ins.store.review)) : ""
                        wrapMode: Text.Wrap
                        color: Theme.text
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: ins.store.review ? ins.store.review.findings : []
                        ColumnLayout {
                            required property var modelData
                            spacing: 0
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: (modelData.severity === "danger" ? "Danger" : modelData.severity === "warn" ? "Warning" : "Note") + " · line " + modelData.line + ": " + modelData.text
                                wrapMode: Text.Wrap
                                color: modelData.severity === "danger" ? Theme.error : Theme.text
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: modelData.snippet
                                font.family: Theme.fontMono
                                wrapMode: Text.WrapAnywhere
                                color: Theme.textMuted
                                Layout.fillWidth: true
                            }
                        }
                    }
                    QQC2.Label {
                        visible: ins.store.review !== null && ins.store.review.problem === ""
                        text: "The recipe is in ~/.cache/bindaru/build/" + (ins.store.review ? ins.store.review.name : "") + ". Installing builds it as you; only the finished package gets administrator rights."
                        wrapMode: Text.Wrap
                        color: Theme.textMuted
                        font.pixelSize: Theme.smallSize * 1.15
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 8
                        QQC2.Button {
                            objectName: "accept-review"
                            visible: ins.store.review !== null && ins.store.review.problem === ""
                            text: "I've read it, install"
                            highlighted: true
                            enabled: !ins.store.busy
                            onClicked: ins.store.acceptReview()
                        }
                        QQC2.Button {
                            objectName: "dismiss-review"
                            text: "Cancel"
                            onClicked: ins.store.review = null
                        }
                    }
                }
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
            ColumnLayout {
                id: deps
                objectName: "dependencies"

                property string tab: ""
                property bool all: false
                readonly property int shownMax: 10
                readonly property var groups: ins.pkg ? Logic.depGroups(ins.pkg, ins.store.installedNames) : []
                readonly property var current: {
                    for (const g of groups)
                        if (g.key === tab)
                            return g;
                    return groups.length > 0 ? groups[0] : null;
                }

                visible: groups.length > 0
                spacing: 8
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                Layout.fillWidth: true

                Connections {
                    target: ins
                    function onPkgChanged() {
                        if (!ins.pkg || ins.pkg.name !== deps.lastName) {
                            deps.all = false;
                            deps.tab = "";
                        }
                        deps.lastName = ins.pkg ? ins.pkg.name : "";
                    }
                }
                property string lastName: ""

                QQC2.Label {
                    text: "Dependencies"
                    font.bold: true
                    color: Theme.text
                }
                Flow {
                    spacing: 6
                    Layout.fillWidth: true
                    Repeater {
                        model: deps.groups
                        Rectangle {
                            id: tabPill
                            required property var modelData
                            readonly property bool on: deps.current !== null && deps.current.key === modelData.key
                            objectName: "dep-tab-" + modelData.key
                            implicitWidth: pillText.implicitWidth + 20
                            implicitHeight: pillText.implicitHeight + 10
                            radius: height / 2
                            color: on ? Theme.accent : pillHover.hovered ? Theme.border : Theme.overlay
                            Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                            signal clicked
                            onClicked: { deps.tab = modelData.key; deps.all = false; }
                            HoverHandler { id: pillHover }
                            TapHandler { onTapped: tabPill.clicked() }
                            QQC2.Label {
                                id: pillText
                                anchors.centerIn: parent
                                text: tabPill.modelData.title + " · " + tabPill.modelData.entries.length
                                color: tabPill.on ? Theme.accentText : Theme.text
                                font.pixelSize: Theme.smallSize * 1.2
                            }
                        }
                    }
                }
                QQC2.Label {
                    text: deps.current ? deps.current.hint : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.smallSize * 1.15
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                Repeater {
                    model: deps.current ? (deps.all ? deps.current.entries : deps.current.entries.slice(0, deps.shownMax)) : []
                    Rectangle {
                        id: dep
                        required property var modelData
                        objectName: "dep-row-" + modelData.name
                        Layout.fillWidth: true
                        implicitHeight: depRow.implicitHeight + 8
                        radius: Theme.radiusControl
                        color: depHover.hovered ? Theme.overlay : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                        HoverHandler { id: depHover }
                        TapHandler { onTapped: ins.store.openDependency(dep.modelData.name) }
                        RowLayout {
                            id: depRow
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 10
                            Tile {
                                name: dep.modelData.name
                                source: ins.store.iconFor(dep.modelData.name)
                                size: 28
                                Layout.alignment: Qt.AlignTop
                            }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                QQC2.Label {
                                    text: dep.modelData.name + (dep.modelData.constraint !== "" ? "  " + dep.modelData.constraint : "")
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                QQC2.Label {
                                    visible: dep.modelData.reason !== ""
                                    text: dep.modelData.reason
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.smallSize * 1.15
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            Chip {
                                text: "Installed"
                                tone: "ok"
                                visible: dep.modelData.installed
                                Layout.alignment: Qt.AlignTop
                            }
                        }
                    }
                }
                QQC2.Button {
                    objectName: "dep-more"
                    visible: deps.current !== null && deps.current.entries.length > deps.shownMax
                    text: deps.all ? "Show fewer" : "Show all " + (deps.current ? deps.current.entries.length : 0)
                    flat: true
                    onClicked: deps.all = !deps.all
                }
            }
        }
    }
}
