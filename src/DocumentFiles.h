// ==============================================================================
// Program: DocumentFiles.h
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: File system abstraction layer for Archi project persistence.
//          Handles safe atomic saves via QSaveFile, concurrency file locking
//          via QLockFile to prevent cross-process clobbering, image rendering
//          export to PNG with strict bounds checking, and backup file creation.
// ==============================================================================
#pragma once

#include <QFile>
#include <QImageWriter>
#include <QLockFile>
#include <QObject>
#include <QSaveFile>
#include <QUrl>
#include <QVariantMap>

class DocumentFiles : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE QUrl folder(const QUrl &url) { return url.resolved(QUrl(".")); }

        // Exports canvas snapshot to PNG image with size validation and smooth scaling
        // Performs atomic disk write using temporary buffer via QSaveFile commit
    Q_INVOKABLE QVariantMap writePng(const QUrl &url, const QImage &image, const QSize &size) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        if (!url.toLocalFile().endsWith(".png", Qt::CaseInsensitive))
            return {{"ok", false}, {"error", "Choose a filename ending in .png"}};
        if (image.isNull())
            return {{"ok", false}, {"error", "Could not render the diagram"}};
        if (size.isEmpty() || size.width() > 4096 || size.height() > 4096)
            return {{"ok", false}, {"error", "Invalid PNG dimensions"}};
        QImage output = image.size() == size ? image
            : image.scaled(size, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        output.setDevicePixelRatio(1);
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

        // Concurrency-safe atomic save utilizing QLockFile and previous content hash verification
    Q_INVOKABLE QVariantMap saveChecked(const QUrl &url, const QString &expected, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QLockFile lock(url.toLocalFile() + ".lock");
        if (!lock.tryLock(0))
            return {{"ok", false}, {"error", "Another board is saving this file"}};
        const auto current = read(url);
        if (!current.value("ok").toBool() || current.value("text").toString() != expected)
            return {{"ok", false}, {"error", "File changed on disk. Save a copy or reload."}};
        const auto backup = write(QUrl::fromLocalFile(url.toLocalFile() + ".bak"), expected);
        if (!backup.value("ok").toBool())
            return backup;
        return write(url, text);
    }

        // Reads project file from local disk with 16 MiB size sanity limit
    Q_INVOKABLE QVariantMap read(const QUrl &url) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        if (file.size() > 16 * 1024 * 1024)
            return {{"ok", false}, {"error", "Project exceeds the 16 MiB file limit"}};
        const auto bytes = file.readAll();
        if (file.error() != QFileDevice::NoError)
            return {{"ok", false}, {"error", file.errorString()}};
        return {{"ok", true}, {"text", QString::fromUtf8(bytes)}};
    }

        // Performs atomic disk write using temporary buffer via QSaveFile commit
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

    Q_INVOKABLE QVariantMap create(const QUrl &url, const QString &text) {
        if (!url.isLocalFile())
            return {{"ok", false}, {"error", "A local file is required"}};
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly))
            return {{"ok", false}, {"error", file.errorString()}};
        const auto bytes = text.toUtf8();
        if (file.write(bytes) != bytes.size() || !file.flush()) {
            const auto error = file.errorString();
            file.remove();
            return {{"ok", false}, {"error", error}};
        }
        return {{"ok", true}};
    }
};
