// ==============================================================================
// Program: png_export.cpp
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Automated regression test suite verifying headless PNG export functionality.
//          Spawns the Archi executable in offscreen software-rendering mode across
//          various project configurations, testing unicode path handling, canvas
//          bounding box clipping, and pixel-color fidelity checks.
//
// How it runs: CMake registers it as ctest `png-export` (see CMakeLists.txt,
// BUILD_TESTING) and passes the built `archi` executable as argv[1]:
//   ctest --test-dir build -R png-export
// It needs no display (QT_QPA_PLATFORM=offscreen, software renderer) and
// does not use the real user's settings (XDG_CONFIG_HOME points into a
// temporary directory). Exit code 0 = all checks passed, 1 = first failure
// (message on stderr).
//
// What the colours mean: #dd6644 = qRgb(221,102,68) first shape,
// #44aa77 = qRgb(68,170,119) second shape, #caffee = qRgb(202,255,238) the
// document background; the arrow and label colours are the exporter's own
// fixed palette values.
// ==============================================================================
#include <QCoreApplication>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTemporaryDir>
#include <QTextStream>
#include <stdexcept>

/** Minimal assertion helper: throws so main()'s catch prints the message and returns 1. */
static void check(bool condition, const char *message)
{
    if (!condition) throw std::runtime_error(message);
}

/** Writes a test fixture file, failing the test if it cannot be created or fully written. */
static void writeFile(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    check(file.open(QIODevice::WriteOnly), "Could not create test fixture");
    check(file.write(bytes) == bytes.size(), "Could not write test fixture");
}

/**
 * Builds one diagram shape JSON object in the on-disk project format.
 * @param id    shapeId (unique per view).
 * @param x,y   Position in canvas units (can be far off-screen or negative).
 * @param color Fill colour as "#rrggbb"; used later to find the shape's pixels.
 * @param kind  shapeKind such as "process" or "decision".
 * Size is fixed at 160x80 canvas units.
 */
static QJsonObject shape(int id, int x, int y, const char *color, const char *kind)
{
    return {{"shapeId", id}, {"px", x}, {"py", y}, {"pw", 160}, {"ph", 80},
            {"shapeColor", color}, {"shapeKind", kind}, {"text", "Node"}};
}

/**
 * Counts pixels in @p image exactly equal to @p color.
 * @param maxY Only scan rows below this y (-1 = whole image); lets a test
 *             look at just the top strip where a distant label lands.
 */
static int pixels(const QImage &image, QRgb color, int maxY = -1)
{
    int count = 0;
    for (int y = 0; y < (maxY < 0 ? image.height() : maxY); ++y)
        for (int x = 0; x < image.width(); ++x)
            if (image.pixel(x, y) == color) ++count;
    return count;
}

/** Runs every PNG export scenario in order; each scenario builds on the prior fixture. */
int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    try {
        check(argc == 2, "Pass the Archi executable path");
        QTemporaryDir temp;
        check(temp.isValid(), "Could not create temporary directory");
        // Spaces and a non-ASCII character in both paths prove URL/path handling is
        // safe for real-world file names.
        const auto input = temp.filePath(QString::fromUtf8("project with spaces é.json"));
        const auto output = temp.filePath(QString::fromUtf8("export with spaces é.png"));
        // Force a deterministic, display-free renderer: offscreen platform plugin,
        // software Qt Quick backend, and 1x scale so pixel counts are stable.
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", "offscreen");
        env.insert("QT_QUICK_BACKEND", "software");
        env.insert("QT_SCALE_FACTOR", "1");
        // Isolate persisted settings (last project, recent list) from the developer's own.
        env.insert("XDG_CONFIG_HOME", temp.filePath("config"));
        // ARCHI_ENTRY would make the app boot a different QML root and skip export.
        env.remove("ARCHI_ENTRY");
        // Runs `archi --export-png source target` and checks it exits 0 (or non-zero
        // when @p success is false). 30 s limit covers slow CI machines.
        auto run = [&](const QString &source, const QString &target, bool success = true) {
            QProcess process;
            process.setProcessEnvironment(env);
            process.start(app.arguments().at(1), {"--export-png", source, target});
            check(process.waitForFinished(30000), "PNG export timed out");
            if (process.exitStatus() != QProcess::NormalExit || (process.exitCode() == 0) != success) {
                QTextStream(stderr) << process.readAllStandardError() << process.readAllStandardOutput();
                throw std::runtime_error("Unexpected PNG export exit status");
            }
        };
        // Two shapes far apart (-500,-250) and (1000,400) plus an arrow routed through
        // points outside the shape box and a two-line label placed far away. The
        // exporter must grow the image to fit all of it, not just the shapes.
        QJsonObject view{{"id", "main"}, {"title", "Main"},
            {"shapes", QJsonArray{shape(1, -500, -250, "#dd6644", "process"),
                                  shape(2, 1000, 400, "#44aa77", "decision")}},
            {"arrows", QJsonArray{QJsonObject{{"fromId", 1}, {"toId", 2},
                {"points", QJsonArray{QJsonObject{{"x", -600}, {"y", 300}},
                                      QJsonObject{{"x", 1000}, {"y", 300}}}},
                {"label", "Connection label\nsecond line"}, {"labelX", 100}, {"labelY", -500}}}}};
        // Whole document: format/version are the values DocumentSync/ProjectWorkspace
        // require; backgroundColor and activeView are exported properties under test.
        QJsonObject document{{"format", "archi-brainstorm"}, {"version", 1},
            {"title", "Export test"}, {"backgroundColor", "#caffee"}, {"activeView", "main"},
            {"views", QJsonArray{view}}};
        // Rewrites the project file from the in-memory `document` object.
        auto saveDocument = [&] { writeFile(input, QJsonDocument(document).toJson()); };
        saveDocument();
        // Scenario 1: baseline export. Checks the PNG is readable, wide enough to
        // contain every offscreen element, painted with the document background, and
        // contains both shapes, the label text and the arrow colours.
        run(input, output);
        const QImage first(output);
        check(!first.isNull(), "Export is not a readable PNG");
        // 1828 px = width of the diagram's bounding box (shapes, routed arrow and
        // label) plus 2 x 32 px margin added by PngExporter.qml; if layout
        // constants change this number must be recomputed, it is not arbitrary.
        check(first.width() == 1828 && first.height() > 1000, "Offscreen shapes, routes or labels were cropped");
        check(first.pixel(0, 0) == qRgb(202, 255, 238), "Background color was lost");
        check(pixels(first, qRgb(221, 102, 68)) > 500, "First shape was not rendered");
        check(pixels(first, qRgb(68, 170, 119)) > 500, "Distant shape was not rendered");
        check(pixels(first, qRgb(57, 70, 81), 100) > 10, "Distant multiline label was not rendered");
        check(pixels(first, qRgb(104, 117, 128)) > 500, "Routed arrow was not rendered");

        // Scenario 2: a wildly different pan/zoom saved in the project must not
        // change the picture; export is of the whole diagram, not the viewport.
        view["viewport"] = QJsonObject{{"x", 9000}, {"y", -8000}, {"zoom", 20}};
        document["views"] = QJsonArray{view};
        saveDocument();
        run(input, output);
        check(QImage(output) == first, "Pan or zoom changed the exported diagram");

        // Scenario 3: a HiDPI screen factor must not change output pixel size.
        env.insert("QT_SCALE_FACTOR", "2");
        run(input, output);
        check(QImage(output).size() == first.size(), "Screen scaling changed PNG dimensions");
        env.insert("QT_SCALE_FACTOR", "1");

        // Scenario 4: protect user data. Exporting onto the project's own path must
        // fail and leave the JSON untouched.
        const auto original = QJsonDocument(document).toJson();
        run(input, input, false);
        QFile source(input);
        check(source.open(QIODevice::ReadOnly) && source.readAll() == original, "Export overwrote the editable project");
        source.close();
        // Scenario 5: failure paths (missing target folder, missing input) must exit
        // non-zero and must not damage a PNG that already exists.
        run(input, temp.filePath("missing-folder/image.png"), false);
        run(temp.filePath("missing.json"), output, false);
        check(!QImage(output).isNull(), "Failed export damaged an existing PNG");

        // Scenario 6: a shape 100000 units away would produce a gigantic image; the
        // exporter must scale it down to the 4096 px cap (DocumentFiles::writePng).
        auto large = shape(2, 100000, 400, "#44aa77", "decision");
        view["shapes"] = QJsonArray{shape(1, 0, 0, "#dd6644", "process"), large};
        document["views"] = QJsonArray{view};
        saveDocument();
        run(input, output);
        const QImage scaled(output);
        check(!scaled.isNull() && scaled.width() <= 4096 && scaled.height() <= 4096,
              "Large diagram exceeded image size limit");

        // Scenario 7: the active view is exported, not the others. An empty view
        // gives the default canvas (576x416 world units + 2 x 32 px margins = 640x480) filled only with the background colour,
        // with no grid and none of the first view's shapes.
        QJsonObject empty{{"id", "empty"}, {"title", "Empty"}, {"shapes", QJsonArray{}}, {"arrows", QJsonArray{}}};
        document["views"] = QJsonArray{view, empty};
        document["activeView"] = "empty";
        saveDocument();
        run(input, output);
        const QImage blank(output);
        check(blank.size() == QSize(640, 480), "The active empty view was not exported");
        check(pixels(blank, qRgb(202, 255, 238)) == 640 * 480, "Empty PNG contains editor grid or other views");
        // Scenario 8: garbage input must fail without replacing the existing PNG.
        writeFile(input, "not a project");
        run(input, output, false);
        check(QImage(output) == blank, "Invalid input replaced the existing PNG");

        QTextStream(stdout) << "PNG export: rendering, bounds, viewport, DPI, active view and file errors passed\n";
        return 0;
    } catch (const std::exception &error) {
        QTextStream(stderr) << error.what() << '\n';
        return 1;
    }
}
