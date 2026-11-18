// Program: archi - DocumentFiles.h
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: C++ helper class that QML uses to read, write, safely save and create project files and to write PNG images, returning a map with ok plus either data or an error message.

#pragma once

// Qt classes for files, image writing, file locks, safe-save files, URLs and key/value maps.
#include <QFile>
#include <QImageWriter>
#include <QLockFile>
#include <QObject>
#include <QSaveFile>
#include <QUrl>
#include <QVariantMap>

/** File access helper exposed to QML as boardFiles. Every method returns a map like {ok: true/false, error: "..."}. */
class DocumentFiles : public QObject {
    // Q_OBJECT lets Qt expose this class to QML.
    Q_OBJECT
public:
    // Reuse the QObject constructor as is.
    using QObject::QObject;
    /** Return the folder that contains the given file URL (resolving "." drops the file name). */
    Q_INVOKABLE QUrl folder(const QUrl &url) { return url.resolved(QUrl(".")); }

    /** Save a rendered image as a PNG of the requested size; checks the target, the image and the size first. */
    Q_INVOKABLE QVariantMap writePng(const QUrl &url, const QImage &image, const QSize &size) {
        // Only files on this computer are allowed, not web addresses.
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        // The name must end in .png.
        if (!url.toLocalFile().endsWith(".png", Qt::CaseInsensitive))
            return {{"ok", false}, {"error", "Choose a filename ending in .png"}};
        // An empty image means rendering failed.
        if (image.isNull())
            return {{"ok", false}, {"error", "Could not render the diagram"}};
        // Reject empty sizes and anything larger than 4096 pixels on a side.
        if (size.isEmpty() || size.width() > 4096 || size.height() > 4096)
            return {{"ok", false}, {"error", "Invalid PNG dimensions"}};
        // Scale the image to the requested size only when it is not already that size.
        QImage output = image.size() == size ? image
            : image.scaled(size, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        // Store it at plain 1x pixel density so the file has exactly the requested pixels.
        output.setDevicePixelRatio(1);
        // QSaveFile writes to a temporary file first so a failed save cannot damage an existing file.
        QSaveFile file(url.toLocalFile());
        if (!file.open(QIODevice::WriteOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        // Encode the image as PNG into the file.
        QImageWriter writer(&file, "png");
        if (!writer.write(output))
            return {{"ok", false}, {"error", writer.errorString()}};
        // commit() swaps the finished temporary file into place.
        if (!file.commit())
            return {{"ok", false}, {"error", file.errorString()}};
        // Report success together with the final size.
        return {{"ok", true}, {"width", output.width()}, {"height", output.height()}};
    }

    /** Save text to a file only if the file on disk still equals what we last loaded (expected), keeping a .bak backup copy. */
    Q_INVOKABLE QVariantMap saveChecked(const QUrl &url, const QString &expected, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        // A lock file stops two windows from saving the same project at once.
        QLockFile lock(url.toLocalFile() + ".lock");
        if (!lock.tryLock(0))
            return {{"ok", false}, {"error", "Another board is saving this file"}};
        // Re-read the file and refuse to overwrite if someone else changed it.
        const auto current = read(url);
        if (!current.value("ok").toBool() || current.value("text").toString() != expected)
            return {{"ok", false}, {"error", "File changed on disk. Save a copy or reload."}};
        // Write the previous contents to a .bak file first.
        const auto backup = write(QUrl::fromLocalFile(url.toLocalFile() + ".bak"), expected);
        if (!backup.value("ok").toBool())
            return backup;
        // Backup is safe, so write the new text.
        return write(url, text);
    }

    /** Read a whole text file (UTF-8), up to a 16 MiB limit. */
    Q_INVOKABLE QVariantMap read(const QUrl &url) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        // Refuse very large files.
        if (file.size() > 16 * 1024 * 1024)
            return {{"ok", false}, {"error", "Project exceeds the 16 MiB file limit"}};
        // Read all bytes and check that reading succeeded.
        const auto bytes = file.readAll();
        if (file.error() != QFileDevice::NoError)
            return {{"ok", false}, {"error", file.errorString()}};
        // Convert the bytes to text and return them.
        return {{"ok", true}, {"text", QString::fromUtf8(bytes)}};
    }

    /** Write text to a file atomically (all or nothing), replacing any existing file. */
    Q_INVOKABLE QVariantMap write(const QUrl &url, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QSaveFile file(url.toLocalFile());
        if (!file.open(QIODevice::WriteOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        // Convert the text to UTF-8 bytes and make sure every byte was written before committing.
        const auto bytes = text.toUtf8();
        if (file.write(bytes) != bytes.size() || !file.commit())
            return {{"ok", false}, {"error", file.errorString()}};
        return {{"ok", true}};
    }

    /** Create a brand-new file with the given text; fails if the file already exists. */
    Q_INVOKABLE QVariantMap create(const QUrl &url, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QFile file(url.toLocalFile());
        // NewOnly makes opening fail instead of overwriting an existing file.
        if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        const auto bytes = text.toUtf8();
        // If writing fails, delete the half-written file so no broken file is left behind.
        if (file.write(bytes) != bytes.size() || !file.flush()) {
            const auto error = file.errorString();
            file.remove();
            return {{"ok", false}, {"error", error}};
        }
        return {{"ok", true}};
    }
};
