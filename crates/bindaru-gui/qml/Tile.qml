// An icon tile: the package's first letter on a colour taken from its name (stable per package).
import QtQuick
import org.bindaru.app

Rectangle {
    id: tile

    property string name: ""
    property int size: 40
    readonly property var hues: [0.02, 0.08, 0.14, 0.33, 0.48, 0.55, 0.62, 0.72, 0.82, 0.93]
    readonly property real hue: {
        let h = 0;
        for (let i = 0; i < name.length; i++)
            h = (h * 31 + name.charCodeAt(i)) % 997;
        return hues[h % hues.length];
    }

    implicitWidth: size
    implicitHeight: size
    radius: Math.max(6, size / 4)
    color: Qt.hsla(hue, 0.45, Theme.bg.hslLightness < 0.5 ? 0.35 : 0.72, 1)

    Text {
        anchors.centerIn: parent
        text: tile.name.length > 0 ? tile.name[0].toUpperCase() : "?"
        font.pixelSize: tile.size * 0.46
        font.bold: true
        color: Theme.bg.hslLightness < 0.5 ? "#ffffff" : "#20262b"
    }
}
