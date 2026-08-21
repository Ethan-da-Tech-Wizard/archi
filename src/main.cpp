#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName("Archi");
    app.setApplicationName("Archi");

    // Fusion is a QML-painted style (not OS-native), so the toolbar looks
    // identical and gets properly defined borders/checked-state highlighting
    // on every target platform, instead of each OS's default Basic-style
    // flat look varying in cleanliness.
    QQuickStyle::setStyle("Fusion");

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                      [](const QList<QQmlError> &warnings) {
        for (const auto &w : warnings)
            qWarning().noquote() << w.toString();
    });

    // ARCHI_ENTRY lets headless test/benchmark harnesses boot an alternate
    // QML entry point (e.g. LogicTest.qml) from the same compiled module,
    // instead of the normal windowed UI.
    const QByteArray entry = qgetenv("ARCHI_ENTRY");
    engine.loadFromModule("Archi", entry.isEmpty() ? "Main" : entry.constData());

    return app.exec();
}
