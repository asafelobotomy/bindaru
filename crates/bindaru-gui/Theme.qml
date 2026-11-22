pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

// Every colour, radius, font size and speed the views use: uQ's shared theme base
// (UqThemeBase.qml, vendored unchanged from uQ's native/uq-consts). On uQ it follows uQ's theme
// tokens (set by Main from backend.themeJson) and Reduce motion; elsewhere the colours are
// Kirigami's colour scheme (the desktop's).
UqThemeBase {
    fallbackRadius: 8
    fallbackColors: {
        const bg = Kirigami.Theme.backgroundColor;
        const fg = Kirigami.Theme.textColor;
        return {
            bg: bg,
            surface: Qt.tint(bg, Qt.alpha(fg, 0.04)),
            surface_alt: Kirigami.Theme.alternateBackgroundColor,
            overlay: Qt.tint(bg, Qt.alpha(fg, 0.08)),
            text: fg,
            text_muted: Qt.tint(bg, Qt.alpha(fg, 0.6)),
            accent: Kirigami.Theme.highlightColor,
            accent_text: Kirigami.Theme.highlightedTextColor,
            border: Qt.tint(bg, Qt.alpha(fg, 0.2)),
            success: Kirigami.Theme.positiveTextColor,
            warning: Kirigami.Theme.neutralTextColor,
            error: Kirigami.Theme.negativeTextColor,
        };
    }
}
