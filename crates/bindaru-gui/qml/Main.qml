// bindaru's window. The layout is AppView; this wires it to the backend and the theme.
import QtQuick
import QtQuick.Controls as QQC2
import org.bindaru.app

QQC2.ApplicationWindow {
    id: win

    width: 1180
    height: 740
    visible: true
    title: "bindaru"
    color: Theme.bg

    Backend { id: backend }
    Store {
        id: store
        backend: backend
        Component.onCompleted: store.load()
    }
    Binding {
        target: Theme
        property: "tokens"
        value: backend.themeJson !== "" ? JSON.parse(backend.themeJson) : ({ present: false })
    }

    AppView {
        anchors.fill: parent
        store: store
    }
}
