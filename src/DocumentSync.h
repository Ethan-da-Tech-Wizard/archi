#pragma once

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QObject>
#include <QSaveFile>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

class DocumentSync : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap report READ report NOTIFY reportChanged)
    struct FileData { QByteArray bytes; QString error; bool exists = false; };
    QString projectPath;
    QByteArray draft;
    QByteArray loadedRevision;
    FileData manifestFile;
    QJsonObject manifest;
    QVariantMap currentReport;
    QFileSystemWatcher watcher;
    QTimer debounce;
    QTimer fallback;

    static FileData read(const QString &path, qint64 limit = 4 * 1024 * 1024) {
        FileData result;
        QFileInfo info(path);
        result.exists = info.exists() || info.isSymLink();
        if (!result.exists) { result.error = "File is missing"; return result; }
        QFile file(path);
        if (!info.isFile() || !file.open(QIODevice::ReadOnly)) {
            result.error = "File is not readable"; return result;
        }
        if (file.size() > limit) { result.error = "File exceeds the sync size limit"; return result; }
        result.bytes = file.read(limit + 1);
        if (file.error() != QFileDevice::NoError || result.bytes.size() > limit)
            result.error = "File could not be read within the sync size limit";
        return result;
    }
    static QString hash(const QByteArray &bytes) {
        return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
    }
    static QVariantMap failure(const QString &error) { return {{"ok", false}, {"error", error}}; }
    static QVariantMap success() { return {{"ok", true}}; }
    static QString write(const QString &path, const QByteArray &bytes) {
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
            return file.errorString();
        return {};
    }
    QString manifestPath() const { return projectPath + ".sync.json"; }
    QString resolve(const QString &path) const {
        return QDir::cleanPath(QFileInfo(projectPath).dir().absoluteFilePath(path));
    }
    static bool textDocument(const QString &path) {
        const auto suffix = QFileInfo(path).suffix().toLower();
        return suffix == "md" || suffix == "txt";
    }
    QString parseManifest() {
        manifest = {{"format", "archi-document-sync"}, {"version", 1}, {"documents", QJsonArray{}}};
        if (!manifestFile.exists) return {};
        if (!manifestFile.error.isEmpty()) return manifestFile.error;
        QJsonParseError error;
        auto parsed = QJsonDocument::fromJson(manifestFile.bytes, &error).object();
        if (error.error != QJsonParseError::NoError || parsed.value("format") != "archi-document-sync"
                || parsed.value("version").toInt() != 1 || !parsed.value("documents").isArray()
                || parsed.value("documents").toArray().size() > 32)
            return "Invalid sync manifest; it has not been replaced";
        QSet<QString> paths;
        for (const auto &value : parsed.value("documents").toArray()) {
            const auto entry = value.toObject();
            const auto path = resolve(entry.value("path").toString());
            const auto role = entry.value("role").toString();
            if (entry.value("path").toString().isEmpty() || !textDocument(path) || paths.contains(path)
                    || (role != "notes" && role != "reference"))
                return "Invalid or duplicate linked document";
            paths.insert(path);
        }
        manifest = parsed;
        return {};
    }
    void watchPaths(const QStringList &paths) {
        QSet<QString> wanted;
        for (const auto &path : paths) {
            if (QFileInfo::exists(path)) wanted.insert(path);
            QString parent = QFileInfo(path).absolutePath();
            while (!QFileInfo::exists(parent) && parent != QFileInfo(parent).absolutePath())
                parent = QFileInfo(parent).absolutePath();
            wanted.insert(parent);
        }
        const auto watched = watcher.files() + watcher.directories();
        for (const auto &path : watched)
            if (!wanted.contains(path)) watcher.removePath(path);
        for (const auto &path : wanted)
            if (!watched.contains(path)) watcher.addPath(path);
    }
    QString persist(const QJsonObject &updated) {
        if (QFileInfo(manifestPath()).isSymLink()) return "Sync-state writes through symbolic links are disabled";
        QLockFile lock(manifestPath() + ".lock");
        if (!lock.tryLock(0)) return "Another window is updating sync state";
        const auto disk = read(manifestPath());
        if (disk.exists != manifestFile.exists || disk.bytes != manifestFile.bytes
                || (disk.exists && !disk.error.isEmpty()))
            return "Sync state changed. Refresh and review again.";
        return write(manifestPath(), QJsonDocument(updated).toJson(QJsonDocument::Indented));
    }
    QVariantMap row(const QString &path) const {
        for (const auto &value : currentReport.value("files").toList())
            if (value.toMap().value("path").toString() == path) return value.toMap();
        return {};
    }
    QString verifyReview(const QString &path, const QString &token) {
        refresh();
        const auto selected = row(path);
        if (selected.isEmpty() || token.isEmpty() || selected.value("token").toString() != token)
            return "Files changed since this review. Refresh and review again.";
        if (!currentReport.value("error").toString().isEmpty()) return currentReport.value("error").toString();
        if (currentReport.value("unsaved").toBool()) return "Save the diagram before confirming alignment";
        if (!selected.value("error").toString().isEmpty()) return selected.value("error").toString();
        return {};
    }
    QString recordReview(const QString &path, const QString &documentHash) {
        auto updated = manifest;
        auto entries = updated.value("documents").toArray();
        for (int i = 0; i < entries.size(); ++i) {
            auto entry = entries[i].toObject();
            if (resolve(entry.value("path").toString()) != path) continue;
            entry["reviewedDocumentHash"] = documentHash;
            entry["reviewedBoardHash"] = currentReport.value("boardHash").toString();
            entry["reviewedAt"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
            entries[i] = entry;
        }
        updated["documents"] = entries;
        return persist(updated);
    }

public:
    explicit DocumentSync(QObject *parent = nullptr) : QObject(parent) {
        debounce.setSingleShot(true);
        debounce.setInterval(180);
        connect(&watcher, &QFileSystemWatcher::fileChanged, this, [this] { debounce.start(); });
        connect(&watcher, &QFileSystemWatcher::directoryChanged, this, [this] { debounce.start(); });
        connect(&debounce, &QTimer::timeout, this, &DocumentSync::refresh);
        fallback.setInterval(5000);
        connect(&fallback, &QTimer::timeout, this, &DocumentSync::refresh);
    }
    QVariantMap report() const { return currentReport; }

    // Content hashes exclude canvas presentation, but retain unknown metadata conservatively.
    static QByteArray semanticBoard(const QByteArray &raw) {
        QJsonParseError error;
        auto data = QJsonDocument::fromJson(raw, &error).object();
        if (error.error != QJsonParseError::NoError || data.value("format") != "archi-brainstorm"
                || data.value("version").toInt() != 1 || !data.value("views").isArray()) return {};
        data.remove("activeView"); data.remove("backgroundColor");
        QJsonArray views;
        for (const auto &value : data.value("views").toArray()) {
            auto view = value.toObject();
            if (!view.value("shapes").isArray() || !view.value("arrows").isArray()) return {};
            view.remove("viewport");
            QJsonArray shapes;
            for (const auto &node : view.value("shapes").toArray()) {
                auto shape = node.toObject();
                for (const auto &key : {"px", "py", "pw", "ph", "shapeColor"}) shape.remove(key);
                for (const auto &key : {"nodeKey", "description", "pseudocode", "linkView"})
                    if (!shape.contains(key)) shape[key] = "";
                shapes.append(shape);
            }
            view["shapes"] = shapes;
            QJsonArray arrows;
            for (const auto &edge : view.value("arrows").toArray()) {
                auto arrow = edge.toObject();
                for (const auto &key : {"points", "labelX", "labelY"}) arrow.remove(key);
                if (!arrow.contains("label")) arrow["label"] = "";
                arrows.append(arrow);
            }
            view["arrows"] = arrows;
            views.append(view);
        }
        data["views"] = views;
        return QJsonDocument(data).toJson(QJsonDocument::Compact);
    }
    Q_INVOKABLE void track(const QUrl &url, const QString &live, const QString &revision) {
        projectPath = url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : QString();
        draft = live.toUtf8();
        loadedRevision = revision.toUtf8();
        refresh();
        if (projectPath.isEmpty()) fallback.stop(); else fallback.start();
    }
    Q_INVOKABLE void updateDraft(const QString &live) {
        draft = live.toUtf8();
        refresh();
    }
    Q_INVOKABLE void refresh() {
        debounce.stop();
        QVariantMap next{{"files", QVariantList{}}, {"attention", 0}, {"error", ""},
                         {"unsaved", false}, {"summary", "Documents not linked"}, {"state", "unlinked"}};
        QStringList paths;
        if (!projectPath.isEmpty()) {
            paths << projectPath << manifestPath();
            const auto disk = read(projectPath, 16 * 1024 * 1024);
            const auto diskSemantic = semanticBoard(disk.bytes);
            const auto liveSemantic = semanticBoard(draft);
            const auto boardHash = hash(liveSemantic);
            QString error = disk.error;
            if (error.isEmpty() && (diskSemantic.isEmpty() || liveSemantic.isEmpty())) error = "Invalid diagram document";
            if (error.isEmpty() && disk.bytes != loadedRevision) error = "Diagram changed on disk. Save a copy or reload.";
            manifestFile = read(manifestPath());
            const auto manifestError = parseManifest();
            if (!manifestError.isEmpty()) error = manifestError;
            next["error"] = error;
            next["boardHash"] = boardHash;
            next["unsaved"] = liveSemantic != diskSemantic;
            QVariantList files;
            int attention = 0;
            for (const auto &value : manifest.value("documents").toArray()) {
                const auto entry = value.toObject();
                const auto path = resolve(entry.value("path").toString());
                paths << path;
                const auto file = read(path);
                const auto docHash = hash(file.bytes);
                const bool reviewed = !entry.value("reviewedBoardHash").toString().isEmpty()
                    && !entry.value("reviewedDocumentHash").toString().isEmpty();
                const bool boardChanged = reviewed && boardHash != entry.value("reviewedBoardHash").toString();
                const bool docChanged = reviewed && docHash != entry.value("reviewedDocumentHash").toString();
                QString state = !file.error.isEmpty() ? "unavailable" : !reviewed ? "unreviewed"
                    : boardChanged && docChanged ? "both-changed" : boardChanged ? "board-changed"
                    : docChanged ? "document-changed" : "current";
                const QString label = state == "unavailable" ? "Document unavailable" : state == "unreviewed" ? "Initial review needed"
                    : state == "both-changed" ? "Both changed" : state == "board-changed" ? "Diagram changed"
                    : state == "document-changed" ? "Document changed" : "Current since review";
                if (state != "current") ++attention;
                const auto token = hash(QJsonDocument(QJsonArray{path, boardHash, hash(disk.bytes), docHash,
                    hash(manifestFile.bytes), file.error, error}).toJson(QJsonDocument::Compact));
                files.append(QVariantMap{{"path", path}, {"url", QUrl::fromLocalFile(path)},
                    {"name", QFileInfo(path).fileName()}, {"role", entry.value("role").toString()},
                    {"state", state}, {"label", label}, {"error", file.error},
                    {"boardChanged", boardChanged}, {"documentChanged", docChanged},
                    {"reviewedAt", entry.value("reviewedAt").toString()}, {"token", token},
                    {"documentHash", docHash}});
            }
            next["files"] = files;
            next["attention"] = attention;
            if (!error.isEmpty()) { next["summary"] = error; next["state"] = "error"; }
            else if (!files.isEmpty()) {
                next["summary"] = attention ? QString("%1 of %2 documents need review").arg(attention).arg(files.size()) : "Documents current since review";
                next["state"] = attention ? "attention" : "current";
            }
        }
        watchPaths(paths);
        if (next != currentReport) { currentReport = next; emit reportChanged(); }
    }
    Q_INVOKABLE QVariantMap linkDocument(const QUrl &url, const QString &role = "notes") {
        refresh();
        if (projectPath.isEmpty()) return failure("Save the project before linking documents");
        if (!currentReport.value("error").toString().isEmpty()) return failure(currentReport.value("error").toString());
        if (!url.isLocalFile() || !textDocument(url.toLocalFile()) || (role != "notes" && role != "reference"))
            return failure("Choose a local Markdown or text document");
        const auto path = QDir::cleanPath(url.toLocalFile());
        const auto file = read(path);
        if (!file.error.isEmpty()) return failure(file.error);
        if (!row(path).isEmpty()) return failure("Document is already linked");
        auto entries = manifest.value("documents").toArray();
        if (entries.size() >= 32) return failure("A project can track up to 32 documents");
        entries.append(QJsonObject{{"path", QFileInfo(projectPath).dir().relativeFilePath(path)}, {"role", role}});
        auto updated = manifest;
        updated["documents"] = entries;
        const auto error = persist(updated);
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }
    Q_INVOKABLE QVariantMap unlinkDocument(const QString &path, const QString &token) {
        refresh();
        if (row(path).value("token").toString() != token || token.isEmpty()) return failure("Sync state changed. Review again.");
        auto updated = manifest;
        QJsonArray entries;
        for (const auto &value : manifest.value("documents").toArray())
            if (resolve(value.toObject().value("path").toString()) != path) entries.append(value);
        updated["documents"] = entries;
        const auto error = persist(updated);
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }
    Q_INVOKABLE QVariantMap confirmAlignment(const QString &path, const QString &token) {
        auto error = verifyReview(path, token);
        if (!error.isEmpty()) return failure(error);
        error = recordReview(path, row(path).value("documentHash").toString());
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }

    static QString flowReference(const QByteArray &raw) {
        const auto data = QJsonDocument::fromJson(raw).object();
        const auto views = data.value("views").toArray();
        auto line = [](QString text) { return text.replace('\n', ' ').replace('\r', ' '); };
        auto key = [](const QJsonObject &view, const QJsonObject &shape) {
            const auto nodeKey = shape.value("nodeKey").toString();
            return nodeKey.isEmpty() ? view.value("id").toString() + "-" + QString::number(shape.value("shapeId").toInt()) : nodeKey;
        };
        int count = 0;
        for (const auto &view : views) count += view.toObject().value("shapes").toArray().size();
        QString text = "# " + line(data.value("title").toString()) + ": Flow Reference\n\n";
        text += QString("%1 views, %2 nodes. Generated from the saved Archi diagram.\n\n").arg(views.size()).arg(count);
        text += "Edit the diagram for structural changes. Manual changes to this reference require sync review.\n\n";
        for (const auto &value : views) {
            const auto view = value.toObject();
            const auto shapes = view.value("shapes").toArray();
            text += "## " + line(view.value("title").toString()) + "\n\n" + view.value("notes").toString() + "\n\n";
            for (const auto &node : shapes) {
                const auto shape = node.toObject();
                text += "### " + line(key(view, shape)) + ": " + line(shape.value("text").toString()) + "\n\n";
                text += shape.value("description").toString() + "\n\n";
                QString code = shape.value("pseudocode").toString() + "\n";
                bool terminal = true;
                for (const auto &edge : view.value("arrows").toArray()) {
                    const auto arrow = edge.toObject();
                    if (arrow.value("fromId") != shape.value("shapeId")) continue;
                    terminal = false;
                    QString target = "MISSING ENDPOINT";
                    for (const auto &destination : shapes)
                        if (destination.toObject().value("shapeId") == arrow.value("toId")) target = key(view, destination.toObject());
                    const auto label = arrow.value("label").toString();
                    code += (label.isEmpty() ? "THEN" : "ON " + label) + " -> " + target + "\n";
                }
                if (terminal) code += "END FLOW\n";
                QString fence = "```";
                while (code.contains(fence)) fence += '`';
                text += fence + "text\n" + code + fence + "\n\n";
                for (const auto &linked : views)
                    if (!shape.value("linkView").toString().isEmpty() && linked.toObject().value("id") == shape.value("linkView"))
                        text += "Detailed flow: " + line(linked.toObject().value("title").toString()) + ".\n\n";
            }
        }
        return text;
    }
    Q_INVOKABLE QVariantMap previewReference(const QString &path) {
        refresh();
        const auto selected = row(path);
        if (selected.value("role") != "reference") return failure("Only a linked flow reference can be generated");
        const auto error = verifyReview(path, selected.value("token").toString());
        if (!error.isEmpty()) return failure(error);
        const auto file = read(path);
        const auto proposed = flowReference(draft);
        if (proposed.toUtf8().size() > 4 * 1024 * 1024) return failure("Generated reference exceeds the 4 MiB limit");
        return {{"ok", true}, {"path", path}, {"token", row(path).value("token")},
                {"current", QString::fromUtf8(file.bytes)}, {"proposed", proposed}};
    }
    Q_INVOKABLE QVariantMap writeReference(const QString &path, const QString &token) {
        auto error = verifyReview(path, token);
        if (!error.isEmpty()) return failure(error);
        if (row(path).value("role") != "reference") return failure("Not a linked flow reference");
        if (QFileInfo(path).isSymLink()) return failure("Reference writes through symbolic links are disabled");
        if (QFileInfo(path + ".sync.bak").isSymLink()) return failure("Backup writes through symbolic links are disabled");
        QLockFile lock(path + ".lock");
        if (!lock.tryLock(0)) return failure("Another window is saving this document");
        const auto previous = read(path);
        if (!previous.error.isEmpty() || hash(previous.bytes) != row(path).value("documentHash").toString())
            return failure("Document changed since the preview");
        const auto proposed = flowReference(draft).toUtf8();
        if (proposed.size() > 4 * 1024 * 1024) return failure("Generated reference exceeds the 4 MiB limit");
        error = write(path + ".sync.bak", previous.bytes);
        if (error.isEmpty()) error = write(path, proposed);
        if (error.isEmpty()) {
            error = recordReview(path, hash(proposed));
            if (!error.isEmpty()) error = "Reference written, but review state was not saved: " + error;
        }
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }
signals:
    void reportChanged();
};
