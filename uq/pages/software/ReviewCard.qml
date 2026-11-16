// The AUR review gate, on screen: what the recipe does that deserves a look, then a button that
// only offers to install the exact recipe (by hash) that was just downloaded.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.uq.settings
import "logic.js" as Logic

ColumnLayout {
    id: card

    property var host
    /// Logic.reviewView: {name, hash, findings, worst, problem}.
    property var review
    signal accepted
    signal dismissed

    spacing: 8

    UqLabel {
        text: "Review " + card.review.name + " (from the AUR)"
        font.bold: true
        Layout.fillWidth: true
    }
    UqLabel {
        text: card.review.problem !== "" ? card.review.problem : Logic.reviewHeadline(card.review)
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    Repeater {
        model: card.review.findings

        ColumnLayout {
            id: finding

            required property var modelData

            spacing: 0
            Layout.fillWidth: true

            UqLabel {
                text: (finding.modelData.severity === "danger" ? "Danger" : finding.modelData.severity === "warn" ? "Warning" : "Note") + " · line " + finding.modelData.line + ": " + finding.modelData.text
                wrapMode: Text.Wrap
                color: finding.modelData.severity === "danger" ? card.host.errorColor() : card.host.textColor()
                Layout.fillWidth: true
            }
            UqLabel {
                text: finding.modelData.snippet
                font.family: "monospace"
                opacity: 0.75
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }
        }
    }
    UqLabel {
        text: "The recipe is in ~/.cache/bindaru/build/" + card.review.name + ". Installing builds it as you; only the finished package gets administrator rights."
        wrapMode: Text.Wrap
        opacity: 0.7
        visible: card.review.problem === ""
        Layout.fillWidth: true
    }
    RowLayout {
        spacing: 8

        QQC2.Button {
            objectName: "accept-review"
            text: "I've read it, install"
            icon.name: "dialog-ok-apply"
            enabled: card.review.hash !== "" && !card.host.busy
            visible: card.review.problem === ""
            onClicked: card.accepted()
        }
        QQC2.Button {
            objectName: "dismiss-review"
            text: "Cancel"
            onClicked: card.dismissed()
        }
    }
}
