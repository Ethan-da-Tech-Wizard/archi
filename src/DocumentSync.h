// Program: archi - DocumentSync.h
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: C++ class that watches an Archi project file and its linked Markdown/text documents, hashes them, reports which ones need review after changes, and can generate a Flow Reference document from the diagram.

#pragma once

// Qt classes for hashing, dates, folders, files, file watching, JSON, locks, safe saving, sets, timers, URLs and maps.
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

/** Tracks sync state between a diagram and its linked documents (stored in a .sync.json file next to the project) and exposes it to QML as projectSync. */
class DocumentSync : public QObject {
    // Q_OBJECT lets Qt expose this class to QML.
    Q_OBJECT
    // The "report" property is what the interface shows; it updates when reportChanged() fires.
    Q_PROPERTY(QVariantMap report READ report NOTIFY reportChanged)
    // Result of reading one file: its bytes, an error text if it failed, and whether it exists.
    struct FileData { QByteArray bytes; QString error; bool exists = false; };
    // Full path of the project (diagram) file being tracked.
    QString projectPath;
    // The unsaved, in-memory text of the diagram.
    QByteArray draft;
    // The exact file bytes that were loaded, used to detect outside changes.
    QByteArray loadedRevision;
    // The sync manifest file as last read from disk.
    FileData manifestFile;
    // The parsed manifest (list of linked documents and when they were last reviewed).
    QJsonObject manifest;
    // The latest report built by refresh().
    QVariantMap currentReport;
    // Watches files and folders so changes are noticed quickly.
    QFileSystemWatcher watcher;
    // Waits a moment after a change so a burst of events triggers one refresh.
    QTimer debounce;
    // A slower timer that refreshes every few seconds in case the watcher missed something.
    QTimer fallback;

    /** Read a file (not a symlink to somewhere else), refusing anything bigger than limit bytes; errors are stored in the result. */
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
    /** SHA-256 fingerprint of some bytes as text; used to tell when contents changed. */
    static QString hash(const QByteArray &bytes) {
        return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
    }
    /** Helpers that build the standard {ok, error} result maps. */
    static QVariantMap failure(const QString &error) { return {{"ok", false}, {"error", error}}; }
    static QVariantMap success() { return {{"ok", true}}; }
    /** Write bytes atomically to a path; returns an empty string on success or the error text. */
    static QString write(const QString &path, const QByteArray &bytes) {
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
            return file.errorString();
        return {};
    }
    /** Path of the sync manifest: the project path plus ".sync.json". */
    QString manifestPath() const { return projectPath + ".sync.json"; }
    /** Turn a path from the manifest (relative to the project folder) into a clean absolute path. */
    QString resolve(const QString &path) const {
        return QDir::cleanPath(QFileInfo(projectPath).dir().absoluteFilePath(path));
    }
    /** Only .md and .txt files may be linked. */
    static bool textDocument(const QString &path) {
        const auto suffix = QFileInfo(path).suffix().toLower();
        return suffix == "md" || suffix == "txt";
    }
    /** Read the manifest bytes into the manifest object, validating format, version, count, paths and roles; returns an error text or empty. */
    QString parseManifest() {
        // Start with an empty, valid manifest.
        manifest = {{"format", "archi-document-sync"}, {"version", 1}, {"documents", QJsonArray{}}};
        // No manifest file yet is fine.
        if (!manifestFile.exists) return {};
        if (!manifestFile.error.isEmpty()) return manifestFile.error;
        // Parse the JSON and check it is the expected format, version 1, with at most 32 documents.
        QJsonParseError error;
        auto parsed = QJsonDocument::fromJson(manifestFile.bytes, &error).object();
        if (error.error != QJsonParseError::NoError || parsed.value("format") != "archi-document-sync"
                || parsed.value("version").toInt() != 1 || !parsed.value("documents").isArray()
                || parsed.value("documents").toArray().size() > 32)
            return "Invalid sync manifest; it has not been replaced";
        // Check every linked document: needs a path, a text file type, no duplicates, and a role of notes or reference.
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
        // Everything checked out, so use it.
        manifest = parsed;
        return {};
    }
    /** Make the file watcher follow exactly these paths (plus the nearest existing parent folder, so new files are noticed). */
    void watchPaths(const QStringList &paths) {
        QSet<QString> wanted;
        for (const auto &path : paths) {
            if (QFileInfo::exists(path)) wanted.insert(path);
            // Watch existing files directly.
            QString parent = QFileInfo(path).absolutePath();
            // Also watch the closest folder that exists, in case the file appears later.
            while (!QFileInfo::exists(parent) && parent != QFileInfo(parent).absolutePath())
                parent = QFileInfo(parent).absolutePath();
            wanted.insert(parent);
        }
        // Stop watching paths we no longer need.
        const auto watched = watcher.files() + watcher.directories();
        for (const auto &path : watched)
            if (!wanted.contains(path)) watcher.removePath(path);
        // Start watching new ones.
        for (const auto &path : wanted)
            if (!watched.contains(path)) watcher.addPath(path);
    }
    /** Save the updated manifest under a lock, but only if the file on disk is still what we loaded; returns an error text or empty. */
    QString persist(const QJsonObject &updated) {
        // Never write through a symbolic link.
        if (QFileInfo(manifestPath()).isSymLink()) return "Sync-state writes through symbolic links are disabled";
        // Lock file prevents two windows from writing at once.
        QLockFile lock(manifestPath() + ".lock");
        if (!lock.tryLock(0)) return "Another window is updating sync state";
        // Make sure nobody changed the manifest since we read it.
        const auto disk = read(manifestPath());
        if (disk.exists != manifestFile.exists || disk.bytes != manifestFile.bytes
                || (disk.exists && !disk.error.isEmpty()))
            return "Sync state changed. Refresh and review again.";
        return write(manifestPath(), QJsonDocument(updated).toJson(QJsonDocument::Indented));
    }
    /** Find the report row for one linked document path (or an empty map). */
    QVariantMap row(const QString &path) const {
        for (const auto &value : currentReport.value("files").toList())
            if (value.toMap().value("path").toString() == path) return value.toMap();
        return {};
    }
    /** Refresh, then confirm the review token still matches so a stale review cannot be confirmed; returns an error text or empty. */
    QString verifyReview(const QString &path, const QString &token) {
        refresh();
        // The token is a fingerprint of everything the user saw; if it differs, something changed.
        const auto selected = row(path);
        if (selected.isEmpty() || token.isEmpty() || selected.value("token").toString() != token)
            return "Files changed since this review. Refresh and review again.";
        // Report-level problems and unsaved diagrams also block the review.
        if (!currentReport.value("error").toString().isEmpty()) return currentReport.value("error").toString();
        if (currentReport.value("unsaved").toBool()) return "Save the diagram before confirming alignment";
        if (!selected.value("error").toString().isEmpty()) return selected.value("error").toString();
        return {};
    }
    /** Store in the manifest that this document was reviewed against the current diagram and document hashes. */
    QString recordReview(const QString &path, const QString &documentHash) {
        auto updated = manifest;
        auto entries = updated.value("documents").toArray();
        for (int i = 0; i < entries.size(); ++i) {
            auto entry = entries[i].toObject();
            if (resolve(entry.value("path").toString()) != path) continue;
            // Record both fingerprints and the time of review.
            entry["reviewedDocumentHash"] = documentHash;
            entry["reviewedBoardHash"] = currentReport.value("boardHash").toString();
            entry["reviewedAt"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
            entries[i] = entry;
        }
        updated["documents"] = entries;
        return persist(updated);
    }

// Everything below is callable from outside the class.
public:
    /** Set up the timers: a short debounce after file events and a slow fallback refresh. */
    explicit DocumentSync(QObject *parent = nullptr) : QObject(parent) {
        debounce.setSingleShot(true);
        debounce.setInterval(180);
        connect(&watcher, &QFileSystemWatcher::fileChanged, this, [this] { debounce.start(); });
        connect(&watcher, &QFileSystemWatcher::directoryChanged, this, [this] { debounce.start(); });
        connect(&debounce, &QTimer::timeout, this, &DocumentSync::refresh);
        fallback.setInterval(5000);
        connect(&fallback, &QTimer::timeout, this, &DocumentSync::refresh);
    }
    /** The latest report for QML. */
    QVariantMap report() const { return currentReport; }

    // Content hashes exclude canvas presentation, but retain unknown metadata conservatively.
    /** Reduce a project file to its meaningful content (dropping positions, colors and viewport) so cosmetic changes do not count as changes. */
    static QByteArray semanticBoard(const QByteArray &raw) {
        QJsonParseError error;
        auto data = QJsonDocument::fromJson(raw, &error).object();
        // Only accept real Archi diagram files of version 1.
        if (error.error != QJsonParseError::NoError || data.value("format") != "archi-brainstorm"
                || data.value("version").toInt() != 1 || !data.value("views").isArray()) return {};
        // Remove display-only settings from the top level.
        data.remove("activeView"); data.remove("backgroundColor");
        QJsonArray views;
        // Clean each view.
        for (const auto &value : data.value("views").toArray()) {
            auto view = value.toObject();
            if (!view.value("shapes").isArray() || !view.value("arrows").isArray()) return {};
            view.remove("viewport");
            // Clean each shape: drop positions and color, and make sure the text fields exist.
            QJsonArray shapes;
            for (const auto &node : view.value("shapes").toArray()) {
                auto shape = node.toObject();
                for (const auto &key : {"px", "py", "pw", "ph", "shapeColor"}) shape.remove(key);
                for (const auto &key : {"nodeKey", "description", "pseudocode", "linkView"})
                    if (!shape.contains(key)) shape[key] = "";
                shapes.append(shape);
            }
            view["shapes"] = shapes;
            // Clean each arrow: drop drawing points and label positions.
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
        // Compact JSON gives a stable text to hash.
        return QJsonDocument(data).toJson(QJsonDocument::Compact);
    }
    /** Start tracking a project: remember its path, the unsaved text and the loaded file contents, then refresh and start the slow timer. */
    Q_INVOKABLE void track(const QUrl &url, const QString &live, const QString &revision) {
        projectPath = url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : QString();
        draft = live.toUtf8();
        loadedRevision = revision.toUtf8();
        refresh();
        if (projectPath.isEmpty()) fallback.stop(); else fallback.start();
    }
    /** Called when the unsaved diagram text changes. */
    Q_INVOKABLE void updateDraft(const QString &live) {
        draft = live.toUtf8();
        refresh();
    }
    /** Rebuild the whole sync report: compare the diagram and every linked document against their last reviewed fingerprints. */
    Q_INVOKABLE void refresh() {
        debounce.stop();
        // Start with an "unlinked" report and fill it in below.
        QVariantMap next{{"files", QVariantList{}}, {"attention", 0}, {"error", ""},
                         {"unsaved", false}, {"summary", "Documents not linked"}, {"state", "unlinked"}};
        QStringList paths;
        // Only do real work when a project is open.
        if (!projectPath.isEmpty()) {
            paths << projectPath << manifestPath();
            // Read the diagram from disk (up to 16 MiB) and fingerprint both the saved and the unsaved versions.
            const auto disk = read(projectPath, 16 * 1024 * 1024);
            const auto diskSemantic = semanticBoard(disk.bytes);
            const auto liveSemantic = semanticBoard(draft);
            const auto boardHash = hash(liveSemantic);
            // Work out any error that should stop reviews.
            QString error = disk.error;
            if (error.isEmpty() && (diskSemantic.isEmpty() || liveSemantic.isEmpty())) error = "Invalid diagram document";
            if (error.isEmpty() && disk.bytes != loadedRevision) error = "Diagram changed on disk. Save a copy or reload.";
            manifestFile = read(manifestPath());
            const auto manifestError = parseManifest();
            if (!manifestError.isEmpty()) error = manifestError;
            // Store the diagram-level results.
            next["error"] = error;
            next["boardHash"] = boardHash;
            next["unsaved"] = liveSemantic != diskSemantic;
            QVariantList files;
            int attention = 0;
            // Check each linked document in the manifest.
            for (const auto &value : manifest.value("documents").toArray()) {
                const auto entry = value.toObject();
                const auto path = resolve(entry.value("path").toString());
                paths << path;
                const auto file = read(path);
                const auto docHash = hash(file.bytes);
                // A document counts as reviewed once both fingerprints are stored.
                const bool reviewed = !entry.value("reviewedBoardHash").toString().isEmpty()
                    && !entry.value("reviewedDocumentHash").toString().isEmpty();
                // Compare current fingerprints with the reviewed ones.
                const bool boardChanged = reviewed && boardHash != entry.value("reviewedBoardHash").toString();
                const bool docChanged = reviewed && docHash != entry.value("reviewedDocumentHash").toString();
                // Choose a state name and a friendly label for the document.
                QString state = !file.error.isEmpty() ? "unavailable" : !reviewed ? "unreviewed"
                    : boardChanged && docChanged ? "both-changed" : boardChanged ? "board-changed"
                    : docChanged ? "document-changed" : "current";
                const QString label = state == "unavailable" ? "Document unavailable" : state == "unreviewed" ? "Initial review needed"
                    : state == "both-changed" ? "Both changed" : state == "board-changed" ? "Diagram changed"
                    : state == "document-changed" ? "Document changed" : "Current since review";
                // Count documents that need attention.
                if (state != "current") ++attention;
                // Token: a fingerprint of everything shown, so later actions can detect stale information.
                const auto token = hash(QJsonDocument(QJsonArray{path, boardHash, hash(disk.bytes), docHash,
                    hash(manifestFile.bytes), file.error, error}).toJson(QJsonDocument::Compact));
                // Add this document's row to the report.
                files.append(QVariantMap{{"path", path}, {"url", QUrl::fromLocalFile(path)},
                    {"name", QFileInfo(path).fileName()}, {"role", entry.value("role").toString()},
                    {"state", state}, {"label", label}, {"error", file.error},
                    {"boardChanged", boardChanged}, {"documentChanged", docChanged},
                    {"reviewedAt", entry.value("reviewedAt").toString()}, {"token", token},
                    {"documentHash", docHash}});
            }
            // Finish the report with a one-line summary and overall state.
            next["files"] = files;
            next["attention"] = attention;
            if (!error.isEmpty()) { next["summary"] = error; next["state"] = "error"; }
            else if (!files.isEmpty()) {
                next["summary"] = attention ? QString("%1 of %2 documents need review").arg(attention).arg(files.size()) : "Documents current since review";
                next["state"] = attention ? "attention" : "current";
            }
        }
        // Keep the watcher in step and tell the interface only if something actually changed.
        watchPaths(paths);
        if (next != currentReport) { currentReport = next; emit reportChanged(); }
    }
    /** Add a Markdown or text document to the manifest with the given role (notes or reference). */
    Q_INVOKABLE QVariantMap linkDocument(const QUrl &url, const QString &role = "notes") {
        refresh();
        // Several checks: saved project, no problems, valid file type and role, readable, not already linked, under the 32 document limit.
        if (projectPath.isEmpty()) return failure("Save the project before linking documents");
        if (!currentReport.value("error").toString().isEmpty()) return failure(currentReport.value("error").toString());
        if (!url.isLocalFile() || !textDocument(url.toLocalFile()) || (role != "notes" && role != "reference"))
            return failure("Choose a local Markdown or text document");
        const auto path = QDir::cleanPath(url.toLocalFile());
        const auto file = read(path);
        if (!file.error.isEmpty()) return failure(file.error);
        if (!row(path).isEmpty()) return failure("Document is already linked");
        // Store the path relative to the project folder.
        auto entries = manifest.value("documents").toArray();
        if (entries.size() >= 32) return failure("A project can track up to 32 documents");
        entries.append(QJsonObject{{"path", QFileInfo(projectPath).dir().relativeFilePath(path)}, {"role", role}});
        auto updated = manifest;
        updated["documents"] = entries;
        const auto error = persist(updated);
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }
    /** Remove a document from the manifest (the token proves the user saw current information). */
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
    /** Record that the user reviewed this document against the current diagram. */
    Q_INVOKABLE QVariantMap confirmAlignment(const QString &path, const QString &token) {
        auto error = verifyReview(path, token);
        if (!error.isEmpty()) return failure(error);
        error = recordReview(path, row(path).value("documentHash").toString());
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }

    /** Build the Markdown text of a Flow Reference from the diagram JSON: each node with its description, pseudocode and outgoing arrows. */
    static QString flowReference(const QByteArray &raw) {
        const auto data = QJsonDocument::fromJson(raw).object();
        const auto views = data.value("views").toArray();
        // Small helpers: line() puts text on one line, key() gives a node its key or a view-id plus number.
        auto line = [](QString text) { return text.replace('\n', ' ').replace('\r', ' '); };
        auto key = [](const QJsonObject &view, const QJsonObject &shape) {
            const auto nodeKey = shape.value("nodeKey").toString();
            return nodeKey.isEmpty() ? view.value("id").toString() + "-" + QString::number(shape.value("shapeId").toInt()) : nodeKey;
        };
        // Count all nodes across views for the intro line.
        int count = 0;
        for (const auto &view : views) count += view.toObject().value("shapes").toArray().size();
        // Document title and intro lines.
        QString text = "# " + line(data.value("title").toString()) + ": Flow Reference\n\n";
        text += QString("%1 views, %2 nodes. Generated from the saved Archi diagram.\n\n").arg(views.size()).arg(count);
        text += "Edit the diagram for structural changes. Manual changes to this reference require sync review.\n\n";
        // One section per view, then one subsection per node.
        for (const auto &value : views) {
            const auto view = value.toObject();
            const auto shapes = view.value("shapes").toArray();
            text += "## " + line(view.value("title").toString()) + "\n\n" + view.value("notes").toString() + "\n\n";
            for (const auto &node : shapes) {
                const auto shape = node.toObject();
                text += "### " + line(key(view, shape)) + ": " + line(shape.value("text").toString()) + "\n\n";
                text += shape.value("description").toString() + "\n\n";
                // Pseudocode block: the node's own pseudocode, then one line per outgoing arrow.
                QString code = shape.value("pseudocode").toString() + "\n";
                bool terminal = true;
                for (const auto &edge : view.value("arrows").toArray()) {
                    const auto arrow = edge.toObject();
                    // Only arrows that start at this node.
                    if (arrow.value("fromId") != shape.value("shapeId")) continue;
                    terminal = false;
                    // Look up the key of the node the arrow points to.
                    QString target = "MISSING ENDPOINT";
                    for (const auto &destination : shapes)
                        if (destination.toObject().value("shapeId") == arrow.value("toId")) target = key(view, destination.toObject());
                    const auto label = arrow.value("label").toString();
                    code += (label.isEmpty() ? "THEN" : "ON " + label) + " -> " + target + "\n";
                }
                // A node with no outgoing arrows ends the flow.
                if (terminal) code += "END FLOW\n";
                // Choose a code fence longer than any run of backticks in the code so the block stays closed.
                QString fence = "```";
                while (code.contains(fence)) fence += '`';
                text += fence + "text\n" + code + fence + "\n\n";
                // Mention a linked detailed view if the node has one.
                for (const auto &linked : views)
                    if (!shape.value("linkView").toString().isEmpty() && linked.toObject().value("id") == shape.value("linkView"))
                        text += "Detailed flow: " + line(linked.toObject().value("title").toString()) + ".\n\n";
            }
        }
        return text;
    }
    /** Generate the proposed new reference text for a linked reference document so QML can show a before/after preview. */
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
    /** Write the generated reference to disk (with a .sync.bak backup and lock) and record the review. */
    Q_INVOKABLE QVariantMap writeReference(const QString &path, const QString &token) {
        auto error = verifyReview(path, token);
        if (!error.isEmpty()) return failure(error);
        if (row(path).value("role") != "reference") return failure("Not a linked flow reference");
        // Refuse to write through symbolic links.
        if (QFileInfo(path).isSymLink()) return failure("Reference writes through symbolic links are disabled");
        if (QFileInfo(path + ".sync.bak").isSymLink()) return failure("Backup writes through symbolic links are disabled");
        // Lock the document while writing.
        QLockFile lock(path + ".lock");
        if (!lock.tryLock(0)) return failure("Another window is saving this document");
        // Make sure it has not changed since the preview.
        const auto previous = read(path);
        if (!previous.error.isEmpty() || hash(previous.bytes) != row(path).value("documentHash").toString())
            return failure("Document changed since the preview");
        const auto proposed = flowReference(draft).toUtf8();
        if (proposed.size() > 4 * 1024 * 1024) return failure("Generated reference exceeds the 4 MiB limit");
        // Back up the old text, then write the new text.
        error = write(path + ".sync.bak", previous.bytes);
        if (error.isEmpty()) error = write(path, proposed);
        if (error.isEmpty()) {
            // Record the new review state; report separately if only that step failed.
            error = recordReview(path, hash(proposed));
            if (!error.isEmpty()) error = "Reference written, but review state was not saved: " + error;
        }
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }
// Qt signal: the report changed.
signals:
    void reportChanged();
};
