#include "bindaru-gui/cpp/app.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQuickWindow>
#include <QString>

void bindaru_describe_application(rust::Str version)
{
    QGuiApplication::setApplicationName(QStringLiteral("bindaru"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("bindaru"));
    QGuiApplication::setApplicationVersion(QString::fromUtf8(version.data(), static_cast<qsizetype>(version.size())));
    QGuiApplication::setDesktopFileName(QStringLiteral("bindaru"));
    // Without a desktop platform theme Qt has no icon theme; fall back to Breeze (Kirigami's own).
    if (QIcon::themeName().isEmpty())
        QIcon::setFallbackThemeName(QStringLiteral("breeze"));
}

bool bindaru_has_window()
{
    const auto windows = QGuiApplication::allWindows();
    for (QWindow *w : windows) {
        if (qobject_cast<QQuickWindow *>(w))
            return true;
    }
    return false;
}
