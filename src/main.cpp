#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QUrl>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, [] { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    // engine.loadFromModule("pyobs.gui", "Main") would be shorter, but it's
    // Qt 6.5+ only and CI currently builds against an older Qt6 (ubuntu-
    // latest's apt package). This is the same qrc path qt_add_qml_module has
    // generated since Qt 6.2, so it works everywhere loadFromModule would.
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/pyobs/gui/Main.qml")));

    return app.exec();
}
