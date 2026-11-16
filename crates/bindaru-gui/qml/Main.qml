// bindaru's window. The layout is AppView; this wires it to the backend and the theme.
import QtQuick
import org.kde.kirigami as Kirigami
import org.bindaru.app

Kirigami.ApplicationWindow {
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
        Component.onCompleted: {
            store.load();
            if (backend.startQuery !== "")
                store.search(backend.startQuery);
        }
    }
    Binding {
        target: Theme
        property: "tokens"
        value: backend.themeJson !== "" ? JSON.parse(backend.themeJson) : ({ present: false })
    }

    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.initialPage: Kirigami.Page {
        padding: 0
        Kirigami.ColumnView.fillWidth: true
        AppView {
            anchors.fill: parent
            store: store
        }
    }
}
