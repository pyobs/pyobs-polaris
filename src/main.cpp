#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // QSettings (config::AppSettings) resolves its on-disk location from
    // these - e.g. ~/.config/pyobs/pyobs-gui++.conf on Linux. Must be set
    // before any QSettings is constructed.
    QCoreApplication::setOrganizationName("pyobs");
    QCoreApplication::setApplicationName("pyobs-gui++");

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, [] { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("pyobs.gui", "Main");

    return app.exec();
}
