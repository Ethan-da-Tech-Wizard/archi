// ==============================================================================
// Program: DocumentSync.h
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Multi-document synchronization and change-tracking engine for Archi.
//          Computes cryptographic/content hashes of diagram state, detects external
//          disk modifications, reconciles concurrent edits across linked workspaces,
//          and maintains audit histories of canvas entity transformations.
//
// How it fits: main.cpp creates one DocumentSync and exposes it to QML as
// `projectSync`. ProjectWorkspace.qml calls track() whenever a project is
// opened or saved and updateDraft() as the user edits; SyncPanel.qml reads the
// `report` property (files, per-file state, summary, error) and calls
// linkDocument / unlinkDocument / confirmAlignment / previewReference /
// writeReference. `archi --sync-status` uses it headlessly.
//
// The idea: a diagram (`PROJECT.json`) can be linked to Markdown/text
// documents (notes, or a generated "flow reference"). Links live in a sidecar
// manifest `PROJECT.json.sync.json`. For each linked document the manifest
// stores the SHA-256 of the diagram's *semantic* content and of the document
// at the time a human last confirmed they agree. Comparing those hashes with
// current ones tells whether the diagram, the document, or both drifted.
//
// Design decisions:
//  * Hashes cover meaning only (see semanticBoard): moving a shape or
//    panning the canvas must not mark documents stale.
//  * Writes are guarded three ways: QLockFile (one writer), re-reading the
//    manifest to detect concurrent edits, and a per-row `token` that a
//    review dialog must echo back, so a confirmation can never apply to
//    files that changed after the user looked.
//  * Symlinked targets are refused so a link cannot redirect a write.
//  * All sizes are capped (documents 4 MiB, diagram 16 MiB, 32 links).
//
// Report `state` values: "unlinked" (no project path), "error", "attention"
// (some documents need review), "current". Per-document states: unavailable,
// unreviewed, both-changed, board-changed, document-changed, current.
//
// Known limits: the class is header-only for Qt's AUTOMOC; all work is
// synchronous on the GUI thread, which is fine for the small capped files.
// ==============================================================================
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

/**
 * Tracks one open project and its linked documents, exposing a QML-bindable
 * status report. One instance per process (see main.cpp).
 *
 * Thread model: GUI thread only. refresh() is cheap enough to run from a
 * 180 ms debounce timer and a 5 s fallback poll.
 */
class DocumentSync : public QObject {
    Q_OBJECT
    // QML binds to `projectSync.report`; reportChanged fires only when the map
    // actually differs (see refresh()), avoiding redundant UI updates.
    Q_PROPERTY(QVariantMap report READ report NOTIFY reportChanged)
    // Result of a size-capped read: file bytes (or empty), a user-facing error
    // string (empty if fine) and whether the path existed at all (distinguishes
    // "missing" from "unreadable" for the manifest).
    struct FileData { QByteArray bytes; QString error; bool exists = false; };
    // Absolute path of the open diagram; empty when the project is unsaved or
    // not a local file, which puts the report in the "unlinked" state.
    QString projectPath;
    // Current in-memory diagram JSON (what the user sees, possibly unsaved).
    QByteArray draft;
    // Exact diagram text as last loaded/saved by the workspace; used to detect
    // that someone else changed the file on disk.
    QByteArray loadedRevision;
    // Raw bytes of the sidecar manifest as last read, compared again before any
    // manifest write to detect a concurrent change.
    FileData manifestFile;
    // Parsed, validated manifest (or the default empty one).
    QJsonObject manifest;
    // Last report handed to QML; used to suppress no-op change notifications.
    QVariantMap currentReport;
    // Notices edits to the diagram, manifest and linked files from other
    // programs or windows.
    QFileSystemWatcher watcher;
    // Coalesces bursts of file events (editors write several times per save)
    // into one refresh 180 ms after the last event.
    QTimer debounce;
    // Safety net: some filesystems (network shares, some editors' rename-based
    // saves) drop watcher events, so also refresh every 5 s while tracking.
    QTimer fallback;

    /**
     * Reads a file with a size cap, never throwing.
     *
     * @param path  Filesystem path.
     * @param limit Maximum accepted size in bytes (default 4 MiB).
     * @return FileData; `error` is non-empty when missing, not a regular file,
     *         unreadable or larger than @p limit. A symlink counts as existing so
     *         the error is "not readable" rather than "missing".
     */
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
        // Read one byte past the limit so a file that grew after the size() check is
        // still caught instead of silently truncated.
        result.bytes = file.read(limit + 1);
        if (file.error() != QFileDevice::NoError || result.bytes.size() > limit)
            result.error = "File could not be read within the sync size limit";
        return result;
    }
    /** Lower-case hex SHA-256 of @p bytes; the identity of a document/diagram. */
    static QString hash(const QByteArray &bytes) {
        return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
    }
    /** Builds the QML failure result `{ok:false, error}`. */
    static QVariantMap failure(const QString &error) { return {{"ok", false}, {"error", error}}; }
    /** Builds the QML success result `{ok:true}`. */
    static QVariantMap success() { return {{"ok", true}}; }
    /**
     * Atomically replaces @p path with @p bytes (QSaveFile temp + rename).
     * @return Empty string on success, otherwise the Qt error message.
     */
    static QString write(const QString &path, const QByteArray &bytes) {
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
            return file.errorString();
        return {};
    }
    /** Sidecar manifest location: the project path with ".sync.json" appended. */
    QString manifestPath() const { return projectPath + ".sync.json"; }
    /**
     * Resolves a manifest path against the project's folder and normalises it
     * (removes ".." and "."). Manifest paths are stored relative so a project
     * folder can be moved or shared without breaking links.
     */
    QString resolve(const QString &path) const {
        return QDir::cleanPath(QFileInfo(projectPath).dir().absoluteFilePath(path));
    }
    /** Only Markdown and plain-text files may be linked (case-insensitive). */
    static bool textDocument(const QString &path) {
        const auto suffix = QFileInfo(path).suffix().toLower();
        return suffix == "md" || suffix == "txt";
    }
    /**
     * Parses and validates the manifest bytes in `manifestFile` into `manifest`.
     *
     * Starts from an empty default so a missing manifest means "no links".
     * Rejects (without touching the file) a manifest with the wrong format or
     * version, more than 32 links, a non-text link, a duplicate path, or a role
     * other than "notes"/"reference".
     *
     * @return Empty string if valid or absent; otherwise a user-facing error. On
     *         error `manifest` keeps the empty default so callers never write
     *         back a half-understood file ("it has not been replaced").
     */
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
    /**
     * Makes the QFileSystemWatcher follow exactly @p paths.
     *
     * Existing files are watched directly; every path also adds its nearest
     * existing parent directory so the watcher notices a file being created or
     * replaced by an editor's delete-and-rename save. Stale entries are removed
     * so the watcher does not leak handles as links change.
     */
    void watchPaths(const QStringList &paths) {
        // De-duplicating set: several paths can share one directory.
        QSet<QString> wanted;
        for (const auto &path : paths) {
            if (QFileInfo::exists(path)) wanted.insert(path);
            // Walk up until a directory exists; stops at the filesystem root, where
            // absolutePath() returns itself (loop guard).
            QString parent = QFileInfo(path).absolutePath();
            while (!QFileInfo::exists(parent) && parent != QFileInfo(parent).absolutePath())
                parent = QFileInfo(parent).absolutePath();
            wanted.insert(parent);
        }
        // Diff against what is currently watched so only changes touch the OS API.
        const auto watched = watcher.files() + watcher.directories();
        for (const auto &path : watched)
            if (!wanted.contains(path)) watcher.removePath(path);
        for (const auto &path : wanted)
            if (!watched.contains(path)) watcher.addPath(path);
    }
    /**
     * Writes a new manifest, refusing if anything changed underneath us.
     *
     * Steps that matter: refuse symlinked manifests; take `<manifest>.lock`
     * without waiting (second window gets an error instead of blocking); then
     * confirm the on-disk manifest still equals the bytes we last read.
     *
     * @param updated Complete manifest object to store.
     * @return Empty string on success, else a user-facing error.
     */
    QString persist(const QJsonObject &updated) {
        if (QFileInfo(manifestPath()).isSymLink()) return "Sync-state writes through symbolic links are disabled";
        QLockFile lock(manifestPath() + ".lock");
        if (!lock.tryLock(0)) return "Another window is updating sync state";
        // Re-read under the lock: another process may have written the manifest
        // since our last refresh().
        const auto disk = read(manifestPath());
        if (disk.exists != manifestFile.exists || disk.bytes != manifestFile.bytes
                || (disk.exists && !disk.error.isEmpty()))
            return "Sync state changed. Refresh and review again.";
        return write(manifestPath(), QJsonDocument(updated).toJson(QJsonDocument::Indented));
    }
    /** Returns the report row for @p path (a resolved absolute path) or an empty map. */
    QVariantMap row(const QString &path) const {
        for (const auto &value : currentReport.value("files").toList())
            if (value.toMap().value("path").toString() == path) return value.toMap();
        return {};
    }
    /**
     * Validates that a review/confirm request is still about the same files.
     *
     * @param path  Resolved path of the linked document.
     * @param token Opaque per-row token from the report the user was shown; it
     *              hashes the diagram, document, manifest and errors, so any
     *              change since the dialog opened invalidates it.
     * @return Empty string if the action may proceed, else a user-facing reason
     *         (stale token, report error, unsaved diagram, document error).
     */
    QString verifyReview(const QString &path, const QString &token) {
        // Recompute from disk first so the token comparison is against fresh state.
        refresh();
        const auto selected = row(path);
        if (selected.isEmpty() || token.isEmpty() || selected.value("token").toString() != token)
            return "Files changed since this review. Refresh and review again.";
        if (!currentReport.value("error").toString().isEmpty()) return currentReport.value("error").toString();
        // An unsaved diagram cannot be "aligned": the saved file and the document
        // would not reflect what the user is looking at.
        if (currentReport.value("unsaved").toBool()) return "Save the diagram before confirming alignment";
        if (!selected.value("error").toString().isEmpty()) return selected.value("error").toString();
        return {};
    }
    /**
     * Marks one linked document as reviewed: stores the current diagram hash,
     * the supplied document hash and a UTC timestamp in its manifest entry.
     *
     * @param path         Resolved path of the document.
     * @param documentHash SHA-256 the document has (or will have) after review.
     * @return Empty string on success, else persist()'s error.
     */
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
    /**
     * Sets up the timers and watcher wiring. Nothing is read until track().
     *
     * @param parent Optional QObject owner.
     */
    explicit DocumentSync(QObject *parent = nullptr) : QObject(parent) {
        // Single-shot so repeated file events keep postponing, not stacking, refreshes.
        debounce.setSingleShot(true);
        debounce.setInterval(180);
        // Both file and directory events feed the same debounce; which one fired
        // does not matter, refresh() re-reads everything.
        connect(&watcher, &QFileSystemWatcher::fileChanged, this, [this] { debounce.start(); });
        connect(&watcher, &QFileSystemWatcher::directoryChanged, this, [this] { debounce.start(); });
        connect(&debounce, &QTimer::timeout, this, &DocumentSync::refresh);
        fallback.setInterval(5000);
        connect(&fallback, &QTimer::timeout, this, &DocumentSync::refresh);
    }
    /** Current report (QML property `report`); see the file header for its keys. */
    QVariantMap report() const { return currentReport; }

    /**
     * Reduces a diagram JSON to the part that carries meaning, for hashing.
     *
     * Removes presentation-only data (active view, background colour, viewport,
     * shape position/size/colour, arrow routing points and label position) and
     * fills missing optional text fields with "" so "absent" and "empty" hash
     * the same. Unknown keys are kept on purpose: an unrecognised field might be
     * meaningful, and ignoring it would hide real changes.
     *
     * @param raw Diagram file bytes (format "archi-brainstorm", version 1).
     * @return Compact JSON bytes, or an empty array if @p raw is not a valid
     *         diagram (callers treat empty as "invalid document").
     */
    static QByteArray semanticBoard(const QByteArray &raw) {
        QJsonParseError error;
        auto data = QJsonDocument::fromJson(raw, &error).object();
        // Return {} (not a partial result) on any shape error so invalid input can
        // never produce a hash that happens to match.
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
    /**
     * Starts (or switches) tracking of a project.
     *
     * @param url      Project file; a non-local URL clears tracking.
     * @param live     Current diagram JSON in memory (may be unsaved).
     * @param revision Exact JSON text last read from or saved to disk; a later
     *                 mismatch with the file means an outside change.
     * Side effects: refreshes the report immediately and starts or stops the
     * fallback poll.
     */
    Q_INVOKABLE void track(const QUrl &url, const QString &live, const QString &revision) {
        projectPath = url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : QString();
        draft = live.toUtf8();
        loadedRevision = revision.toUtf8();
        refresh();
        if (projectPath.isEmpty()) fallback.stop(); else fallback.start();
    }
    /** Updates the in-memory diagram (called as the user edits) and refreshes. */
    Q_INVOKABLE void updateDraft(const QString &live) {
        draft = live.toUtf8();
        refresh();
    }
    /**
     * Recomputes the whole report and publishes it if it changed.
     *
     * Reads the diagram and manifest, compares semantic hashes against each
     * linked document's recorded review hashes and sets the per-file state and
     * the overall summary. Invokable from QML for the manual refresh button.
     */
    Q_INVOKABLE void refresh() {
        debounce.stop();
        // Defaults describe the "no project" case; the block below overwrites them.
        QVariantMap next{{"files", QVariantList{}}, {"attention", 0}, {"error", ""},
                         {"unsaved", false}, {"summary", "Documents not linked"}, {"state", "unlinked"}};
        // Paths to watch for changes, collected while we read.
        QStringList paths;
        if (!projectPath.isEmpty()) {
            // Always watch the diagram and manifest even if a linked file is broken.
            paths << projectPath << manifestPath();
            // Diagram is allowed to be larger (16 MiB) than linked documents (4 MiB).
            const auto disk = read(projectPath, 16 * 1024 * 1024);
            const auto diskSemantic = semanticBoard(disk.bytes);
            const auto liveSemantic = semanticBoard(draft);
            // Hash the *live* semantic content so the hash is stable across layout-only edits.
            const auto boardHash = hash(liveSemantic);
            QString error = disk.error;
            // Error precedence: unreadable file, then invalid JSON, then changed on
            // disk, then a manifest problem (the last assignment wins so a bad manifest
            // is always reported).
            if (error.isEmpty() && (diskSemantic.isEmpty() || liveSemantic.isEmpty())) error = "Invalid diagram document";
            if (error.isEmpty() && disk.bytes != loadedRevision) error = "Diagram changed on disk. Save a copy or reload.";
            manifestFile = read(manifestPath());
            const auto manifestError = parseManifest();
            if (!manifestError.isEmpty()) error = manifestError;
            next["error"] = error;
            next["boardHash"] = boardHash;
            // Unsaved = the in-memory diagram means something different from the file.
            next["unsaved"] = liveSemantic != diskSemantic;
            // One report row per linked document.
            QVariantList files;
            int attention = 0;
            for (const auto &value : manifest.value("documents").toArray()) {
                const auto entry = value.toObject();
                const auto path = resolve(entry.value("path").toString());
                paths << path;
                const auto file = read(path);
                const auto docHash = hash(file.bytes);
                // "Reviewed" requires both stored hashes; a link never confirmed is
                // "unreviewed" regardless of content.
                const bool reviewed = !entry.value("reviewedBoardHash").toString().isEmpty()
                    && !entry.value("reviewedDocumentHash").toString().isEmpty();
                const bool boardChanged = reviewed && boardHash != entry.value("reviewedBoardHash").toString();
                const bool docChanged = reviewed && docHash != entry.value("reviewedDocumentHash").toString();
                // Decision table: unavailable > unreviewed > both/board/document changed > current.
                QString state = !file.error.isEmpty() ? "unavailable" : !reviewed ? "unreviewed"
                    : boardChanged && docChanged ? "both-changed" : boardChanged ? "board-changed"
                    : docChanged ? "document-changed" : "current";
                // Human-readable text for the same state, shown in SyncPanel.
                const QString label = state == "unavailable" ? "Document unavailable" : state == "unreviewed" ? "Initial review needed"
                    : state == "both-changed" ? "Both changed" : state == "board-changed" ? "Diagram changed"
                    : state == "document-changed" ? "Document changed" : "Current since review";
                if (state != "current") ++attention;
                // Token binds a row to the exact state it was computed from; it is hashed
                // over every input that could change what a review would mean.
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
            // Overall state: errors dominate, then documents needing attention.
            if (!error.isEmpty()) { next["summary"] = error; next["state"] = "error"; }
            else if (!files.isEmpty()) {
                next["summary"] = attention ? QString("%1 of %2 documents need review").arg(attention).arg(files.size()) : "Documents current since review";
                next["state"] = attention ? "attention" : "current";
            }
        }
        // Keep the watcher in step with the (possibly changed) link list.
        watchPaths(paths);
        // Compare maps, not just hashes, so QML bindings fire only on real change.
        if (next != currentReport) { currentReport = next; emit reportChanged(); }
    }
    /**
     * Adds a Markdown/text file to the manifest.
     *
     * @param url  Local file URL of the document.
     * @param role "notes" (free-form) or "reference" (generated flow reference).
     * @return `{ok:true}` or `{ok:false, error}` for: unsaved project, existing
     *         report error, non-local/non-text file, unreadable file, duplicate
     *         link, or more than 32 links.
     * The path is stored relative to the project folder.
     */
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
    /**
     * Removes a link. @p token must match the row's current token (the user
     * must have seen the up-to-date state). Does not delete the document.
     * @return `{ok:true}` or `{ok:false, error}`.
     */
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
    /**
     * Records that the user confirms diagram and document agree, using the
     * document's current hash. Refused when the token is stale, the diagram is
     * unsaved, or a report error exists (see verifyReview).
     * @return `{ok:true}` or `{ok:false, error}`.
     */
    Q_INVOKABLE QVariantMap confirmAlignment(const QString &path, const QString &token) {
        auto error = verifyReview(path, token);
        if (!error.isEmpty()) return failure(error);
        error = recordReview(path, row(path).value("documentHash").toString());
        refresh();
        return error.isEmpty() ? success() : failure(error);
    }

    /**
     * Renders the diagram as a Markdown "Flow Reference" document.
     *
     * Output: a title, counts, then per view a section, and per node a heading
     * (nodeKey, or "viewId-shapeId" when no key), its description, and a
     * fenced text block with its pseudocode followed by one line per outgoing
     * arrow ("THEN -> target" or "ON label -> target"; "END FLOW" when it has
     * none). Nodes linking to another view get a "Detailed flow" line.
     *
     * Deterministic for a given diagram so repeated generation is diffable.
     *
     * @param raw Diagram JSON bytes.
     * @return Markdown text.
     */
    static QString flowReference(const QByteArray &raw) {
        const auto data = QJsonDocument::fromJson(raw).object();
        const auto views = data.value("views").toArray();
        // Single-line form for headings: embedded newlines would break Markdown
        // structure.
        auto line = [](QString text) { return text.replace('\n', ' ').replace('\r', ' '); };
        // Stable identifier for a node: the user's nodeKey if set.
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
                // Make the code fence longer than any backtick run inside the pseudocode,
                // otherwise user text could close the fence early (CommonMark rule).
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
    /**
     * Generates a flow reference for a linked "reference" document and returns
     * both versions for a side-by-side preview. Writes nothing.
     *
     * @return `{ok, path, token, current, proposed}` or `{ok:false, error}`;
     *         fails if the generated text would exceed 4 MiB.
     */
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
    /**
     * Overwrites a linked "reference" document with the freshly generated flow
     * reference, after the user approved the preview.
     *
     * Safety: stale-token check, role check, symlink refusal for the document
     * and its backup, a lock file, and a re-hash of the document under the lock.
     * The previous content is saved to `<doc>.sync.bak` first. On success the
     * new text is recorded as reviewed.
     *
     * @return `{ok:true}` or `{ok:false, error}`. If only the review bookkeeping
     *         fails the message says the reference WAS written.
     */
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
/** Emitted after the report map changes; QML re-evaluates `report` bindings. */
signals:
    void reportChanged();
};
