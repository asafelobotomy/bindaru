#include "bindaru-gui/cpp/app.h"

#include <QGuiApplication>
#include <QQuickWindow>
#include <QString>

void bindaru_describe_application(rust::Str version)
{
    QGuiApplication::setApplicationName(QStringLiteral("bindaru"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("bindaru"));
    QGuiApplication::setApplicationVersion(QString::fromUtf8(version.data(), static_cast<qsizetype>(version.size())));
    QGuiApplication::setDesktopFileName(QStringLiteral("bindaru"));
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
