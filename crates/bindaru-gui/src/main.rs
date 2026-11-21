//! bindaru's window: sidebar, header with search, package view and inspector (Qt Quick). On uQ it
//! takes its colours from uQ's theme tokens; elsewhere it follows the desktop palette.
//!
//! Exit codes: 0 normal, 4 no window could be created.

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};

mod app;
mod backend;
mod theme;
#[allow(dead_code)] // vendored whole; this app uses part of it
#[rustfmt::skip]
mod uq_theme;

fn main() {
    // The "Basic" Qt Quick Controls style draws from the palette, which Theme overrides per item.
    QQuickStyle::set_style(&QString::from("Basic"));
    let mut app = QGuiApplication::new();
    app::ffi::bindaru_describe_application(env!("CARGO_PKG_VERSION"));
    // A second start brings the open window forward instead of opening another (two windows could
    // start two pacman transactions at once).
    if app::ffi::bindaru_forward_to_running() {
        return;
    }
    // Qt 6.4 doesn't search qrc:/qt/qml on its own (6.5 does); the app's module lives there.
    // SAFETY: no other thread exists yet.
    unsafe { std::env::set_var("QML_IMPORT_PATH", ":/qt/qml") };
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/org/bindaru/app/qml/Main.qml"));
    }
    if !app::ffi::bindaru_has_window() {
        eprintln!("bindaru-gui: the window couldn't be created (is Qt Quick installed?)");
        std::process::exit(4);
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
