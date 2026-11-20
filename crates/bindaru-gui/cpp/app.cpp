#include "bindaru-gui/cpp/app.h"

#include <QGuiApplication>
#include <QDir>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
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

namespace {
// The session's bindaru socket: in $XDG_RUNTIME_DIR, which only this user can reach. Empty when
// there is none, and then every start gets its own window, as before.
QString instanceSocket()
{
    const QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (dir.isEmpty() || !QDir::isAbsolutePath(dir) || !QDir(dir).exists())
        return {};
    return dir + QStringLiteral("/bindaru-gui.socket");
}

void bringForward()
{
    const auto windows = QGuiApplication::allWindows();
    for (QWindow *w : windows) {
        if (!qobject_cast<QQuickWindow *>(w))
            continue;
        if (w->windowState() & Qt::WindowMinimized)
            w->setWindowStates(w->windowStates() & ~Qt::WindowMinimized);
        w->show();
        w->raise();
        w->requestActivate();
    }
}
} // namespace

bool bindaru_forward_to_running()
{
    const QString path = instanceSocket();
    if (path.isEmpty())
        return false;
    {
        QLocalSocket probe;
        probe.connectToServer(path);
        if (probe.waitForConnected(1000)) {
            probe.write("show\n");
            probe.waitForBytesWritten(1000);
            probe.disconnectFromServer();
            return true;
        }
    }
    // Nobody answered: a socket left by a copy that crashed is stale, so take it over.
    auto *server = new QLocalServer(qApp);
    server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!server->listen(path)) {
        QLocalServer::removeServer(path);
        if (!server->listen(path)) {
            qWarning("bindaru-gui: can't listen on %s (%s); a second start will open a second window",
                     qPrintable(path), qPrintable(server->errorString()));
            return false;
        }
    }
    QObject::connect(server, &QLocalServer::newConnection, server, [server] {
        while (QLocalSocket *peer = server->nextPendingConnection()) {
            QObject::connect(peer, &QLocalSocket::disconnected, peer, &QObject::deleteLater);
            bringForward();
        }
    });
    QObject::connect(qApp, &QCoreApplication::aboutToQuit, server, [server] { server->close(); });
    return false;
}
