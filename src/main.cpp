// ==============================================================================
// Program: main.cpp
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Main entry point and CLI controller for Archi desktop application.
//          Initializes the Qt/QML application engine, registers C++ helper types
//          into QML context, parses command line arguments for headless operations
//          (such as --sync-status and --export-png), and boots the main canvas view.
//
// How it fits: this is the only translation unit with main(). It owns the
// three C++ helpers (DocumentFiles, MathEngine, DocumentSync) for the whole
// process lifetime and exposes them to QML as the context properties
// `boardFiles`, `mathEngine` and `projectSync`, which every qml/*.qml file
// uses by those exact names. The QML module "Archi" (see CMakeLists.txt)
// supplies ProjectWorkspace.qml, the default window.
//
// Command-line modes (all exit codes are documented where returned):
//   archi                          open the normal window, restore last project
//   archi PROJECT.json             open that project instead
//   archi --sync-status PROJECT    headless: print sync report JSON, no GUI
//   archi --export-png P.json O.png  load, render to PNG via PngExporter.qml, quit
// Environment: ARCHI_ENTRY=<QML type> boots an alternate root (test harness).
//
// Known limits: argument parsing is positional and minimal on purpose; unknown
// flags are treated as file names.
// ==============================================================================
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

/**
 * Program entry point; dispatches between headless CLI modes and the GUI.
 *
 * @param argc Argument count from the OS.
 * @param argv Argument vector; argv[1] selects the mode (see file header).
 * @return 0 on success. 64 (EX_USAGE from sysexits.h) for wrong argument
 *         counts. For --sync-status: 0 = "current", 1 = "error", 2 = any
 *         other state ("attention" or "unlinked"), so scripts can branch on it.
 *         In GUI mode: the Qt event loop's exit code, or -1 if QML failed to
 *         load.
 */
int main(int argc, char *argv[])
{
    // Headless branch: checked first, before any GUI object exists, because a
    // QGuiApplication would try to connect to a display server and fail on CI
    // machines and over SSH.
    if (argc >= 2 && QByteArray(argv[1]) == "--sync-status") {
        // QCoreApplication is enough here (no windows) and lets us use
        // app.arguments(), which is already decoded from the platform encoding.
        QCoreApplication app(argc, argv);
        if (argc != 3) {
            QTextStream(stderr) << "Usage: archi --sync-status PROJECT.json\n";
            return 64;
        }
        // Absolute path first: the sync tracker keys files by URL, so relative
        // spellings of the same file must collapse to one entry.
        const auto url = QUrl::fromLocalFile(QFileInfo(app.arguments().at(2)).absoluteFilePath());
        DocumentFiles files;
        const auto file = files.read(url);
        DocumentSync sync;
        // The file's current text is passed as both "disk" and "saved" snapshots,
        // i.e. we ask "is this file self-consistent right now", not "did an editor
        // change it" (there is no editor in headless mode).
        sync.track(url, file.value("text").toString(), file.value("text").toString());
        QTextStream(stdout) << QJsonDocument::fromVariant(sync.report()).toJson(QJsonDocument::Indented);
        // The report's "state" field is the machine-readable summary; the full JSON
        // printed above is for humans and tools.
        const auto state = sync.report().value("state").toString();
        return state == "current" ? 0 : state == "error" ? 1 : 2;
    }
    // GUI branch. The QML `Settings` objects (last project, recent list) key
    // their stored values by these two names, so changing them would silently
    // forget users' saved preferences.
    QGuiApplication app(argc, argv);
    app.setOrganizationName("Archi");
    app.setApplicationName("Archi");
    // Export mode needs exactly: program, flag, project, image (4 arguments).
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

    // The helpers live on the stack of main() so they outlive the engine's
    // use of them; QML only borrows raw pointers via setContextProperty, so
    // they must be declared before the engine and never destroyed early.
    DocumentFiles files;
    MathEngine math;
    DocumentSync sync;
    QQmlApplicationEngine engine;
    // Names here are part of the QML API surface (used as bare identifiers in
    // qml/*.qml); renaming one requires updating every QML file.
    engine.rootContext()->setContextProperty("boardFiles", &files);
    engine.rootContext()->setContextProperty("mathEngine", &math);
    engine.rootContext()->setContextProperty("projectSync", &sync);
    // QML `Qt.quit()` / `Qt.exit(n)` must reach the C++ event loop, otherwise
    // the window closes but the process keeps running.
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    QObject::connect(&engine, &QQmlEngine::exit, &app, &QCoreApplication::exit);
    // If the root QML object fails to instantiate (syntax or import error),
    // exit with -1 instead of hanging on an empty event loop. Queued so the
    // exit happens after the engine finishes its own failure handling.
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    // Surface QML warnings on stderr; without this handler some load-time
    // warnings are swallowed when running headless in CI.
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                      [](const QList<QQmlError> &warnings) {
        for (const auto &w : warnings)
            qWarning().noquote() << w.toString();
    });

    // ARCHI_ENTRY lets headless test/benchmark harnesses boot an alternate
    // QML entry point (e.g. LogicTest.qml) from the same compiled module,
    // instead of the normal windowed UI.
    const QByteArray entry = qgetenv("ARCHI_ENTRY");
    // Export mode: pre-seed the root object's properties so ProjectWorkspace
    // loads the given project and writes the PNG on its own. Persistence flags
    // are disabled so a one-shot export never changes the user's saved settings
    // or writes autosave files.
    if (exportPng) {
        engine.setInitialProperties({
            {"documentUrl", QUrl::fromLocalFile(QFileInfo(app.arguments().at(2)).absoluteFilePath())},
            {"pngExportTarget", QUrl::fromLocalFile(QFileInfo(app.arguments().at(3)).absoluteFilePath())},
            {"restoreLastProject", false}, {"rememberProjects", false}, {"autoSave", false}
        });
    // Single file argument: open it directly. Skipped when ARCHI_ENTRY is set
    // because the alternate entry type has no `documentUrl` property.
    } else if (entry.isEmpty() && app.arguments().size() == 2)
        engine.setInitialProperties({{"documentUrl", QUrl::fromLocalFile(QFileInfo(app.arguments().at(1)).absoluteFilePath())}, {"restoreLastProject", false}});
    // Load by module + type name (Qt 6.5+ API) so the same binary can start
    // ProjectWorkspace, the export path, or a test entry without recompiling.
    engine.loadFromModule("Archi", exportPng || entry.isEmpty() ? "ProjectWorkspace" : entry.constData());

    // Blocks until the window closes or QML calls quit/exit.
    return app.exec();
}
