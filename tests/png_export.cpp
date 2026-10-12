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

static void check(bool condition, const char *message)
{
    if (!condition) throw std::runtime_error(message);
}

static void writeFile(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    check(file.open(QIODevice::WriteOnly), "Could not create test fixture");
    check(file.write(bytes) == bytes.size(), "Could not write test fixture");
}

static QJsonObject shape(int id, int x, int y, const char *color, const char *kind)
{
    return {{"shapeId", id}, {"px", x}, {"py", y}, {"pw", 160}, {"ph", 80},
            {"shapeColor", color}, {"shapeKind", kind}, {"text", "Node"}};
}

static int pixels(const QImage &image, QRgb color, int maxY = -1)
{
    int count = 0;
    for (int y = 0; y < (maxY < 0 ? image.height() : maxY); ++y)
        for (int x = 0; x < image.width(); ++x)
            if (image.pixel(x, y) == color) ++count;
    return count;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    try {
        check(argc == 2, "Pass the Archi executable path");
        QTemporaryDir temp;
        check(temp.isValid(), "Could not create temporary directory");
        const auto input = temp.filePath(QString::fromUtf8("project with spaces é.json"));
        const auto output = temp.filePath(QString::fromUtf8("export with spaces é.png"));
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", "offscreen");
        env.insert("QT_QUICK_BACKEND", "software");
        env.insert("QT_SCALE_FACTOR", "1");
        env.insert("XDG_CONFIG_HOME", temp.filePath("config"));
        env.remove("ARCHI_ENTRY");
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
        QJsonObject view{{"id", "main"}, {"title", "Main"},
            {"shapes", QJsonArray{shape(1, -500, -250, "#dd6644", "process"),
                                  shape(2, 1000, 400, "#44aa77", "decision")}},
            {"arrows", QJsonArray{QJsonObject{{"fromId", 1}, {"toId", 2},
                {"points", QJsonArray{QJsonObject{{"x", -600}, {"y", 300}},
                                      QJsonObject{{"x", 1000}, {"y", 300}}}},
                {"label", "Connection label\nsecond line"}, {"labelX", 100}, {"labelY", -500}}}}};
        QJsonObject document{{"format", "archi-brainstorm"}, {"version", 1},
            {"title", "Export test"}, {"backgroundColor", "#caffee"}, {"activeView", "main"},
            {"views", QJsonArray{view}}};
        auto saveDocument = [&] { writeFile(input, QJsonDocument(document).toJson()); };
        saveDocument();
        run(input, output);
        const QImage first(output);
        check(!first.isNull(), "Export is not a readable PNG");
        check(first.width() == 1828 && first.height() > 1000, "Offscreen shapes, routes or labels were cropped");
        check(first.pixel(0, 0) == qRgb(202, 255, 238), "Background color was lost");
        check(pixels(first, qRgb(221, 102, 68)) > 500, "First shape was not rendered");
        check(pixels(first, qRgb(68, 170, 119)) > 500, "Distant shape was not rendered");
        check(pixels(first, qRgb(57, 70, 81), 100) > 10, "Distant multiline label was not rendered");
        check(pixels(first, qRgb(104, 117, 128)) > 500, "Routed arrow was not rendered");

        view["viewport"] = QJsonObject{{"x", 9000}, {"y", -8000}, {"zoom", 20}};
        document["views"] = QJsonArray{view};
        saveDocument();
        run(input, output);
        check(QImage(output) == first, "Pan or zoom changed the exported diagram");

        env.insert("QT_SCALE_FACTOR", "2");
        run(input, output);
        check(QImage(output).size() == first.size(), "Screen scaling changed PNG dimensions");
        env.insert("QT_SCALE_FACTOR", "1");

        const auto original = QJsonDocument(document).toJson();
        run(input, input, false);
        QFile source(input);
        check(source.open(QIODevice::ReadOnly) && source.readAll() == original, "Export overwrote the editable project");
        source.close();
        run(input, temp.filePath("missing-folder/image.png"), false);
        run(temp.filePath("missing.json"), output, false);
        check(!QImage(output).isNull(), "Failed export damaged an existing PNG");

        auto large = shape(2, 100000, 400, "#44aa77", "decision");
        view["shapes"] = QJsonArray{shape(1, 0, 0, "#dd6644", "process"), large};
        document["views"] = QJsonArray{view};
        saveDocument();
        run(input, output);
        const QImage scaled(output);
        check(!scaled.isNull() && scaled.width() <= 4096 && scaled.height() <= 4096,
              "Large diagram exceeded image size limit");

        QJsonObject empty{{"id", "empty"}, {"title", "Empty"}, {"shapes", QJsonArray{}}, {"arrows", QJsonArray{}}};
        document["views"] = QJsonArray{view, empty};
        document["activeView"] = "empty";
        saveDocument();
        run(input, output);
        const QImage blank(output);
        check(blank.size() == QSize(640, 480), "The active empty view was not exported");
        check(pixels(blank, qRgb(202, 255, 238)) == 640 * 480, "Empty PNG contains editor grid or other views");
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
