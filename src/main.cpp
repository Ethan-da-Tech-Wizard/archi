// Program: archi - main.cpp
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: Entry point of the Archi desktop app: handles the --sync-status and --export-png command-line modes, otherwise sets up Qt Quick, exposes the C++ helper objects to QML and starts the user interface.

// Our own C++ helper classes: saving/loading files, running math, and tracking file sync.
#include "DocumentFiles.h"
#include "MathEngine.h"
#include "DocumentSync.h"
// Qt classes for files, the QML engine, the GUI application, window styles, icons, debug output and text streams.
#include <QFileInfo>
#include <QQmlContext>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>
#include <QTextStream>

/** Program start. Returns 0 on success, 64 for bad command-line usage, other values for errors. */
int main(int argc, char *argv[])
{
    // Command-line mode: print whether a project file is in sync, without opening any window.
    if (argc >= 2 && QByteArray(argv[1]) == "--sync-status") {
        // A console-only application object is enough because no GUI is shown.
        QCoreApplication app(argc, argv);
        if (argc != 3) {
            // Wrong number of arguments: show usage and exit with the conventional "usage error" code.
            QTextStream(stderr) << "Usage: archi --sync-status PROJECT.json\n";
            return 64;
        }
        // Turn the given path into a full file URL.
        const auto url = QUrl::fromLocalFile(QFileInfo(app.arguments().at(2)).absoluteFilePath());
        DocumentFiles files;
        // Read the file and start tracking it, then print the sync report as JSON.
        const auto file = files.read(url);
        DocumentSync sync;
        sync.track(url, file.value("text").toString(), file.value("text").toString());
        QTextStream(stdout) << QJsonDocument::fromVariant(sync.report()).toJson(QJsonDocument::Indented);
        // Exit code tells scripts the result: 0 current, 1 error, 2 anything else (out of date or changed).
        const auto state = sync.report().value("state").toString();
        return state == "current" ? 0 : state == "error" ? 1 : 2;
    }
    // Normal start: create the GUI application and give it a name for saved settings.
    QGuiApplication app(argc, argv);
    app.setOrganizationName("Archi");
    app.setApplicationName("Archi");
    // Check whether the user asked to export a PNG picture of a project.
    const bool exportPng = app.arguments().value(1) == "--export-png";
    // --export-png needs exactly a project file and an output image.
    if (exportPng && app.arguments().size() != 4) {
        QTextStream(stderr) << "Usage: archi --export-png PROJECT.json IMAGE.png\n";
        return 64;
    }

    // Fusion is a QML-painted style (not OS-native), so the toolbar looks
    // identical and gets properly defined borders/checked-state highlighting
    // on every target platform, instead of each OS's default Basic-style
    // flat look varying in cleanliness.
    QQuickStyle::setStyle("Fusion");
// Create the helper objects and the QML engine that loads the interface.

    DocumentFiles files;
    MathEngine math;
    DocumentSync sync;
    QQmlApplicationEngine engine;
    // Make the C++ objects visible to QML under these names: boardFiles, mathEngine, projectSync.
    engine.rootContext()->setContextProperty("boardFiles", &files);
    engine.rootContext()->setContextProperty("mathEngine", &math);
    engine.rootContext()->setContextProperty("projectSync", &sync);
    // Let QML code quit or exit the application.
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    QObject::connect(&engine, &QQmlEngine::exit, &app, &QCoreApplication::exit);
    // If the interface fails to load, exit with an error code instead of hanging.
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    // Print any QML warnings to the console.
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                      [](const QList<QQmlError> &warnings) {
        for (const auto &w : warnings)
            qWarning().noquote() << w.toString();
    });

    // ARCHI_ENTRY lets headless test/benchmark harnesses boot an alternate
    // QML entry point (e.g. LogicTest.qml) from the same compiled module,
    // instead of the normal windowed UI.
    const QByteArray entry = qgetenv("ARCHI_ENTRY");
    // Optional environment variable that selects a different starting QML screen.
    if (exportPng) {
        // Export mode: pass the project path and image path to the QML workspace and turn off remembering and autosave.
        engine.setInitialProperties({
            {"documentUrl", QUrl::fromLocalFile(QFileInfo(app.arguments().at(2)).absoluteFilePath())},
            {"pngExportTarget", QUrl::fromLocalFile(QFileInfo(app.arguments().at(3)).absoluteFilePath())},
            {"restoreLastProject", false}, {"rememberProjects", false}, {"autoSave", false}
        });
    // Opening a single file argument loads that project, without reopening the last one.
    } else if (entry.isEmpty() && app.arguments().size() == 2)
        engine.setInitialProperties({{"documentUrl", QUrl::fromLocalFile(QFileInfo(app.arguments().at(1)).absoluteFilePath())}, {"restoreLastProject", false}});
    // Load the chosen QML screen from the Archi module (the normal workspace unless a test entry was requested).
    engine.loadFromModule("Archi", exportPng || entry.isEmpty() ? "ProjectWorkspace" : entry.constData());

    // Run the event loop until the window closes.
    return app.exec();
}
