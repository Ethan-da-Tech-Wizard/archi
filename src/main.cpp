#include "DocumentFiles.h"
#include "MathEngine.h"
#include "DocumentSync.h"
#include <QFileInfo>
#include <QQmlContext>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>
#include <QTextStream>

int main(int argc, char *argv[])
{
    if (argc >= 2 && QByteArray(argv[1]) == "--sync-status") {
        QCoreApplication app(argc, argv);
        if (argc != 3) {
            QTextStream(stderr) << "Usage: archi --sync-status PROJECT.json\n";
            return 64;
        }
        const auto url = QUrl::fromLocalFile(QFileInfo(app.arguments().at(2)).absoluteFilePath());
        DocumentFiles files;
        const auto file = files.read(url);
        DocumentSync sync;
        sync.track(url, file.value("text").toString(), file.value("text").toString());
        QTextStream(stdout) << QJsonDocument::fromVariant(sync.report()).toJson(QJsonDocument::Indented);
        const auto state = sync.report().value("state").toString();
        return state == "current" ? 0 : state == "error" ? 1 : 2;
    }
    QGuiApplication app(argc, argv);
    app.setOrganizationName("Archi");
    app.setApplicationName("Archi");
    const bool exportPng = app.arguments().value(1) == "--export-png";
    if (exportPng && app.arguments().size() != 4) {
        QTextStream(stderr) << "Usage: archi --export-png PROJECT.json IMAGE.png\n";
        return 64;
    }

    // Fusion is a QML-painted style (not OS-native), so the toolbar looks
    // identical and gets properly defined borders/checked-state highlighting
    // on every target platform, instead of each OS's default Basic-style
    // flat look varying in cleanliness.
    QQuickStyle::setStyle("Fusion");

    DocumentFiles files;
    MathEngine math;
    DocumentSync sync;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("boardFiles", &files);
    engine.rootContext()->setContextProperty("mathEngine", &math);
    engine.rootContext()->setContextProperty("projectSync", &sync);
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    QObject::connect(&engine, &QQmlEngine::exit, &app, &QCoreApplication::exit);
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
    if (exportPng) {
        engine.setInitialProperties({
            {"documentUrl", QUrl::fromLocalFile(QFileInfo(app.arguments().at(2)).absoluteFilePath())},
            {"pngExportTarget", QUrl::fromLocalFile(QFileInfo(app.arguments().at(3)).absoluteFilePath())},
            {"restoreLastProject", false}, {"rememberProjects", false}, {"autoSave", false}
        });
    } else if (entry.isEmpty() && app.arguments().size() == 2)
        engine.setInitialProperties({{"documentUrl", QUrl::fromLocalFile(QFileInfo(app.arguments().at(1)).absoluteFilePath())}, {"restoreLastProject", false}});
    engine.loadFromModule("Archi", exportPng || entry.isEmpty() ? "ProjectWorkspace" : entry.constData());

    return app.exec();
}
