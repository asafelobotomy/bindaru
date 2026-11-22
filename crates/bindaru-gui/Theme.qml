pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

// Every colour, radius and font the views use. On uQ these come from uQ's theme tokens (set by
// Main from backend.themeJson); elsewhere from Kirigami's colour scheme (the desktop's).
QtObject {
    id: theme

    property var tokens: ({ present: false })
    readonly property bool uq: tokens.present === true

    function pick(key, fallback) {
        return uq && tokens.colors && tokens.colors[key] ? tokens.colors[key] : fallback;
    }

    readonly property color bg: pick("bg", Kirigami.Theme.backgroundColor)
    readonly property color surface: pick("surface", Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(Kirigami.Theme.textColor, 0.04)))
    readonly property color surfaceAlt: pick("surface_alt", Kirigami.Theme.alternateBackgroundColor)
    readonly property color overlay: pick("overlay", Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(Kirigami.Theme.textColor, 0.08)))
    readonly property color text: pick("text", Kirigami.Theme.textColor)
    readonly property color textMuted: pick("text_muted", Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(Kirigami.Theme.textColor, 0.6)))
    readonly property color accent: pick("accent", Kirigami.Theme.highlightColor)
    readonly property color accentText: pick("accent_text", Kirigami.Theme.highlightedTextColor)
    readonly property color border: pick("border", Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(Kirigami.Theme.textColor, 0.2)))
    readonly property color success: pick("success", Kirigami.Theme.positiveTextColor)
    readonly property color warning: pick("warning", Kirigami.Theme.neutralTextColor)
    readonly property color error: pick("error", Kirigami.Theme.negativeTextColor)

    readonly property int radius: uq && tokens.radius ? tokens.radius : 8
    readonly property string fontUi: uq && tokens.fontUi ? tokens.fontUi : ""
    readonly property string fontMono: uq && tokens.fontMono ? tokens.fontMono : "monospace"
    readonly property real bodySize: uq && tokens.fontSize ? tokens.fontSize : Qt.application.font.pointSize
    readonly property real smallSize: Math.max(7, bodySize - 1)
    readonly property real headingSize: Math.round(bodySize * 1.4)

    // Motion: the same speeds and curves as uQ's shell (uQ shell/core/Motion.qml), so the
    // app's hovers, fades and slides move like the desktop's. Use these, not literal ms.
    // Hover, press and focus feedback; things going away.
    readonly property int motionFast: 100
    // Moves, slides, toasts and things coming in.
    readonly property int motionBase: 140
    // Large surfaces: a whole page or panel.
    readonly property int motionSlow: 220
    // Arriving or moving things start quick and settle.
    readonly property int easing: Easing.OutCubic
}
