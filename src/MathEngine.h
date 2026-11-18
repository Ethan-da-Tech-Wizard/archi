// Program: archi - MathEngine.h
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: C++ class that runs the Python math helper in a separate process with a time and output budget and exposes the result, error and busy state to the QML user interface.

#pragma once
// Qt building blocks: JSON encoding/decoding, QObject base, running an external process, and a timer.
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>

/** Runs one math calculation at a time in a child Python process and reports back to QML through properties and the changed() signal. */
class MathEngine : public QObject {
    // Q_OBJECT lets Qt generate the signal/property machinery for this class.
    Q_OBJECT
    // Properties QML can read; each one re-reads when changed() is emitted.
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString result READ result NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // The child process that runs math_engine.py.
    QProcess process;
    // Watchdog timer that kills the process if it runs too long.
    QTimer timer;
    // Bytes the helper has printed so far (its JSON answer).
    QByteArray output;
    // The JSON request that will be written to the helper once it starts.
    QByteArray request;
    // Last successful answer text.
    QString resultText;
    // Last error message (empty when there is no error).
    QString errorText;
public:
    /** Wire up all the process and timer reactions once, when the object is created. */
    explicit MathEngine(QObject *parent = nullptr) : QObject(parent) {
        // The timer fires only once per calculation.
        timer.setSingleShot(true);
        // Time budget exceeded: remember why, then stop the helper.
        connect(&timer, &QTimer::timeout, this, [this] {
            errorText = "Calculation exceeded its time budget";
            process.kill();
        });
        // When the helper starts, send it the request and close its input so it knows the request is complete.
        connect(&process, &QProcess::started, this, [this] {
            process.write(request);
            process.closeWriteChannel();
            emit changed();
        });
        // Collect whatever the helper prints; refuse to keep more than 64 KiB.
        connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
            output += process.readAllStandardOutput();
            if (output.size() > 65536) {
                errorText = "Result exceeded its output budget";
                process.kill();
            }
        });
        // If the helper cannot even launch (for example Python is missing), report that.
        connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                timer.stop();
                errorText = "Local math environment is unavailable";
                emit changed();
            }
        });
        // When the helper exits, read its JSON answer and set either the result or an error.
        connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
            timer.stop();
            output += process.readAllStandardOutput();
            if (errorText.isEmpty()) {
                // Only parse the output if nothing already went wrong (timeout, cancel, size limit).
                const auto data = QJsonDocument::fromJson(output).object();
                // A non-zero exit code, abnormal exit or empty answer means the helper crashed or hit its limits.
                if (code != 0 || status != QProcess::NormalExit || data.isEmpty())
                    errorText = "Calculation failed or exceeded its resource budget";
                // The helper reported success, so keep its result text.
                else if (data.value("ok").toBool())
                    resultText = data.value("result").toString();
                else
                    // The helper reported a problem, so keep its error text.
                    errorText = data.value("error").toString();
            }
            emit changed();
        });
    }
    /** Make sure the child process is gone before this object is destroyed. */
    ~MathEngine() override { process.kill(); process.waitForFinished(1000); }
    /** True while the helper process is starting or running. */
    bool busy() const { return process.state() != QProcess::NotRunning; }
    /** The last result text. */
    QString result() const { return resultText; }
    /** The last error text. */
    QString error() const { return errorText; }
    /** Start a calculation (ignored if one is already running); callable from QML. */
    Q_INVOKABLE void calculate(const QString &expression, const QString &operation, const QString &variable) {
        // Only one calculation at a time.
        if (busy()) return;
        // Clear the previous answer before starting a new one.
        resultText.clear(); errorText.clear(); output.clear();
        // Pack the three inputs into one compact JSON object to send to the helper.
        request = QJsonDocument(QJsonObject{{"expression", expression}, {"operation", operation}, {"variable", variable}}).toJson(QJsonDocument::Compact);
        // Launch Python in isolated mode (-I) running the math script; both paths are filled in at build time by the build system.
        process.start(QStringLiteral(ARCHI_MATH_PYTHON), {"-I", QStringLiteral(ARCHI_MATH_SCRIPT)});
        // Start the 6 second watchdog.
        timer.start(6000);
        emit changed();
    }
    /** Stop the running calculation early; callable from QML. */
    Q_INVOKABLE void cancel() {
        if (!busy()) return;
        errorText = "Cancelled";
        timer.stop();
        process.kill();
    }
// Qt signal announcing that busy, result or error may have changed.
signals:
    void changed();
};
