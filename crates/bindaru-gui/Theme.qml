pragma Singleton
import QtQuick

// Every colour, radius and font the views use. On uQ these come from uQ's theme tokens (set by
// Main from backend.themeJson); elsewhere from the desktop's palette.
QtObject {
    id: theme

    property var tokens: ({ present: false })
    readonly property bool uq: tokens.present === true
    readonly property SystemPalette pal: SystemPalette { colorGroup: SystemPalette.Active }

    function pick(key, fallback) {
        return uq && tokens.colors && tokens.colors[key] ? tokens.colors[key] : fallback;
    }

    readonly property color bg: pick("bg", pal.window)
    readonly property color surface: pick("surface", pal.base)
    readonly property color surfaceAlt: pick("surface_alt", pal.alternateBase)
    readonly property color overlay: pick("overlay", Qt.tint(pal.window, Qt.alpha(pal.text, 0.08)))
    readonly property color text: pick("text", pal.windowText)
    readonly property color textMuted: pick("text_muted", Qt.tint(pal.window, Qt.alpha(pal.windowText, 0.6)))
    readonly property color accent: pick("accent", pal.highlight)
    readonly property color accentText: pick("accent_text", pal.highlightedText)
    readonly property color border: pick("border", Qt.tint(pal.window, Qt.alpha(pal.windowText, 0.2)))
    readonly property color success: pick("success", "#2e9e5b")
    readonly property color warning: pick("warning", "#d98a1f")
    readonly property color error: pick("error", "#d1424f")

    readonly property int radius: uq && tokens.radius ? tokens.radius : 8
    readonly property string fontUi: uq && tokens.fontUi ? tokens.fontUi : ""
    readonly property string fontMono: uq && tokens.fontMono ? tokens.fontMono : "monospace"
    readonly property real bodySize: uq && tokens.fontSize ? tokens.fontSize : Qt.application.font.pointSize
    readonly property real smallSize: Math.max(7, bodySize - 1)
    readonly property real headingSize: Math.round(bodySize * 1.4)
}
