use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    let files = [
        "qml/Main.qml",
        "qml/AppView.qml",
        "qml/Store.qml",
        "qml/HeaderBar.qml",
        "qml/Sidebar.qml",
        "qml/PackageList.qml",
        "qml/Inspector.qml",
        "qml/Card.qml",
        "qml/SettingsPage.qml",
        "qml/ReposPage.qml",
        "qml/ScanPage.qml",
        "qml/Tile.qml",
        "qml/Chip.qml",
        "qml/logic.js",
    ];
    let mut module = QmlModule::new("org.bindaru.app").qml_files(files.map(QmlFile::from));
    module = module.qml_files([
        QmlFile::from("Theme.qml").singleton(true),
        QmlFile::from("UqThemeBase.qml"),
    ]);
    CxxQtBuilder::new_qml_module(module)
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("Network")
        .files(["src/backend.rs", "src/app.rs"])
        .cpp_file("cpp/app.cpp")
        .build();
}
