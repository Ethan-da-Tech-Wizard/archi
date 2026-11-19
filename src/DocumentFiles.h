// ==============================================================================
// Program: DocumentFiles.h
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: File system abstraction layer for Archi project persistence.
//          Handles safe atomic saves via QSaveFile, concurrency file locking
//          via QLockFile to prevent cross-process clobbering, image rendering
//          export to PNG with strict bounds checking, and backup file creation.
//
// How it fits: main.cpp creates one DocumentFiles and exposes it to QML as
// the context property `boardFiles`. ProjectWorkspace.qml (create/open/save)
// and PngExporter.qml (PNG export) call these Q_INVOKABLE methods; DocumentSync
// reads project files itself and does not use this class.
//
// Common contract: every method returns a QVariantMap (becomes a JS object in
// QML) with `ok: bool`. On failure `error` holds a human-readable message that
// the UI shows verbatim; on success extra keys (text, width, height) may be
// present. Nothing here throws, because QML cannot catch C++ exceptions.
//
// Design decisions: all writes go through QSaveFile (write to a temp file,
// then rename) so a crash or full disk never leaves a half-written project.
// Only local file URLs are accepted; remote URLs are rejected up front.
//
// Known limits: files are handled as UTF-8 text; the read size cap is 16 MiB
// and PNG output is capped at 4096x4096 so a runaway diagram cannot exhaust
// memory.
// ==============================================================================
#pragma once

#include <QFile>
#include <QImageWriter>
#include <QLockFile>
#include <QObject>
#include <QSaveFile>
#include <QUrl>
#include <QVariantMap>

/**
 * Stateless file I/O facade exposed to QML as `boardFiles`.
 *
 * Owned by main(); not copyable state, so a single instance serves all QML.
 * Threading: all calls run on the GUI thread and block until done, which is
 * acceptable because project files are capped at 16 MiB.
 */
class DocumentFiles : public QObject {
    Q_OBJECT
public:
    // Inherit QObject's constructors (parent pointer) without restating them.
    using QObject::QObject;
    /**
     * Returns the directory containing @p url (resolving "." against it).
     * Used by file dialogs to start in the project's folder. Pure; no disk access.
     */
    Q_INVOKABLE QUrl folder(const QUrl &url) { return url.resolved(QUrl(".")); }

    /**
     * Writes a rendered canvas snapshot to a PNG file.
     *
     * @param url   Destination; must be a local `file:` URL ending in `.png`
     *              (case-insensitive) so a project file cannot be overwritten by
     *              a mistyped extension.
     * @param image Rendered diagram from QML's grabToImage.
     * @param size  Final pixel size, each side 1..4096. If it differs from the
     *              image size the image is rescaled (smooth, aspect NOT kept; the
     *              caller already computed matching proportions).
     * @return `{ok:true, width, height}` or `{ok:false, error}`.
     *
     * Side effects: replaces the destination atomically; on any failure an
     * existing PNG is left untouched (tests/png_export.cpp pins this down).
     */
    Q_INVOKABLE QVariantMap writePng(const QUrl &url, const QImage &image, const QSize &size) {
        // Reject remote URLs before touching the filesystem.
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        // Guards against exporting over a .json project by accident.
        if (!url.toLocalFile().endsWith(".png", Qt::CaseInsensitive))
            return {{"ok", false}, {"error", "Choose a filename ending in .png"}};
        // A null image means QML failed to render (e.g. zero-size item).
        if (image.isNull())
            return {{"ok", false}, {"error", "Could not render the diagram"}};
        // Upper bound keeps memory bounded: 4096*4096*4 bytes is about 64 MiB.
        if (size.isEmpty() || size.width() > 4096 || size.height() > 4096)
            return {{"ok", false}, {"error", "Invalid PNG dimensions"}};
        // Skip the costly resample when QML already rendered at the target size.
        QImage output = image.size() == size ? image
            : image.scaled(size, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        // PNG metadata should describe a 1x image so viewers do not rescale it on
        // HiDPI displays; the QML side may have rendered at the screen's ratio.
        output.setDevicePixelRatio(1);
        // QSaveFile buffers into a temp file; nothing reaches the target until
        // commit() succeeds.
        QSaveFile file(url.toLocalFile());
        if (!file.open(QIODevice::WriteOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        QImageWriter writer(&file, "png");
        if (!writer.write(output))
            return {{"ok", false}, {"error", writer.errorString()}};
        if (!file.commit())
            return {{"ok", false}, {"error", file.errorString()}};
        return {{"ok", true}, {"width", output.width()}, {"height", output.height()}};
    }

    /**
     * Saves @p text to @p url only if the file on disk still equals @p expected.
     *
     * This is optimistic concurrency control: the workspace remembers the text it
     * last loaded or saved (@p expected). If another window or program changed the
     * file in between, the save is refused instead of silently overwriting.
     *
     * @param url      Local project file URL.
     * @param expected Exact text last read from or written to @p url.
     * @param text     New content to write.
     * @return `{ok:true}` or `{ok:false, error}`.
     *
     * Side effects: creates `<file>.lock` while saving and writes
     * `<file>.bak` containing the previous content before replacing the file.
     */
    Q_INVOKABLE QVariantMap saveChecked(const QUrl &url, const QString &expected, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        // Lock is released when `lock` goes out of scope (RAII). tryLock(0) means
        // "do not wait": a second window gets an immediate error instead of a hang.
        QLockFile lock(url.toLocalFile() + ".lock");
        if (!lock.tryLock(0))
            return {{"ok", false}, {"error", "Another board is saving this file"}};
        // Compare under the lock so no one can slip in a write between the check and
        // our write.
        const auto current = read(url);
        if (!current.value("ok").toBool() || current.value("text").toString() != expected)
            return {{"ok", false}, {"error", "File changed on disk. Save a copy or reload."}};
        // Keep a one-deep backup of the version we are about to replace.
        const auto backup = write(QUrl::fromLocalFile(url.toLocalFile() + ".bak"), expected);
        // If the backup cannot be written, abort: losing the user's old data
        // silently is worse than a failed save.
        if (!backup.value("ok").toBool())
            return backup;
        return write(url, text);
    }

    /**
     * Reads a project file as UTF-8 text.
     *
     * @param url Local project file URL.
     * @return `{ok:true, text}` or `{ok:false, error}`; fails when the file is
     *         larger than 16 MiB (a sanity cap, real diagrams are far smaller) or
     *         unreadable.
     */
    Q_INVOKABLE QVariantMap read(const QUrl &url) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        // Checked before readAll() so an oversized file is never loaded into memory.
        if (file.size() > 16 * 1024 * 1024)
            return {{"ok", false}, {"error", "Project exceeds the 16 MiB file limit"}};
        const auto bytes = file.readAll();
        // readAll() can fail midway (e.g. disk removed); surface that as an error.
        if (file.error() != QFileDevice::NoError)
            return {{"ok", false}, {"error", file.errorString()}};
        return {{"ok", true}, {"text", QString::fromUtf8(bytes)}};
    }

    /**
     * Writes @p text to @p url atomically (temp file + rename via QSaveFile).
     *
     * Unlike saveChecked() this does no conflict check or backup; it is used for
     * first saves, "save as" and for writing the backup itself.
     *
     * @return `{ok:true}` or `{ok:false, error}`.
     */
    Q_INVOKABLE QVariantMap write(const QUrl &url, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QSaveFile file(url.toLocalFile());
        if (!file.open(QIODevice::WriteOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        const auto bytes = text.toUtf8();
        if (file.write(bytes) != bytes.size() || !file.commit())
            return {{"ok", false}, {"error", file.errorString()}};
        return {{"ok", true}};
    }

    /**
     * Creates a NEW file containing @p text; fails if the path already exists.
     *
     * QIODevice::NewOnly maps to O_EXCL, so two windows creating the same name
     * cannot both succeed and nobody's existing file is overwritten.
     *
     * @return `{ok:true}` or `{ok:false, error}`. A partial file is removed if
     *         the write or flush fails.
     */
    Q_INVOKABLE QVariantMap create(const QUrl &url, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        const auto bytes = text.toUtf8();
        // Do not leave a truncated project behind after a failed write.
        if (file.write(bytes) != bytes.size() || !file.flush()) {
            const auto error = file.errorString();
            file.remove();
            return {{"ok", false}, {"error", error}};
        }
        return {{"ok", true}};
    }
};
