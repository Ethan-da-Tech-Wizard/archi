// ==============================================================================
// Program: MathEngine.h
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Asynchronous C++/Qt bridge connecting the diagramming GUI to the
//          isolated Python SymPy mathematical engine subprocess. Manages process
//          lifecycles, enforces execution timeouts, buffers standard I/O, and
//          emits reactive Qt signals upon calculation completion or error.
//
// How it fits: main.cpp exposes one instance to QML as `mathEngine`. The
// "Calculate" dialog in ProjectWorkspace.qml calls calculate()/cancel() and
// binds to `busy`, `result` and `error`. The worker is src/math_engine.py;
// the interpreter and script paths arrive as the compile-time macros
// ARCHI_MATH_PYTHON and ARCHI_MATH_SCRIPT defined in CMakeLists.txt.
//
// Design decisions: a fresh process per request (no shared state, the OS
// reclaims memory), the request goes in on stdin as JSON and the reply comes
// back on stdout, so no expression text ever appears on a command line or in
// a shell. A 6 s timer and a 64 KiB output cap bound a runaway calculation;
// the script also sets its own OS limits.
//
// Known limits: one calculation at a time (calculate() is ignored while busy);
// requires the `.venv-math` virtualenv with SymPy to exist.
// ==============================================================================
#pragma once
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>

/**
 * Runs symbolic maths in a sandboxed Python child process and reports the
 * outcome through QML-bindable properties.
 *
 * Properties: `busy` (child running), `result` (text of the last success),
 * `error` (message of the last failure; empty on success). All three emit
 * the single `changed` signal. GUI thread only.
 */
class MathEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString result READ result NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // The child process handle; owned by this object so it is killed on destruction.
    QProcess process;
    // Watchdog: kills the child if it runs past its time budget.
    QTimer timer;
    // Accumulated stdout of the child (a JSON reply arrives in chunks).
    QByteArray output;
    // JSON request kept until the child has started, because it can only be
    // written to stdin after QProcess::started fires.
    QByteArray request;
    // Backing fields for the `result` and `error` properties.
    QString resultText;
    QString errorText;
public:
    /**
     * Wires the process and timer signals once at construction.
     * @param parent Optional QObject owner.
     */
    explicit MathEngine(QObject *parent = nullptr) : QObject(parent) {
        // Watchdog: a hung or exponential calculation is killed rather than left
        // running. The error text is set first so the `finished` handler below
        // reports "time budget" instead of the generic failure message.
        timer.setSingleShot(true);
        connect(&timer, &QTimer::timeout, this, [this] {
            errorText = "Calculation exceeded its time budget";
            process.kill();
        });
        // Hand the request over only once the process really exists, then close
        // stdin so Python's read() sees end-of-file and starts computing.
        connect(&process, &QProcess::started, this, [this] {
            process.write(request);
            process.closeWriteChannel();
            emit changed();
        });
        // Buffer partial output; a reply larger than 64 KiB means something is
        // wrong (the script caps results at 16000 chars), so abort the child.
        connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
            output += process.readAllStandardOutput();
            if (output.size() > 65536) {
                errorText = "Result exceeded its output budget";
                process.kill();
            }
        });
        // Only FailedToStart is handled here: for crashes or kills the `finished`
        // signal also fires and reports them, so handling both would double-emit.
        connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                timer.stop();
                errorText = "Local math environment is unavailable";
                emit changed();
            }
        });
        // Single place where a run ends (success, error, crash, timeout or cancel).
        connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
            timer.stop();
            // Drain whatever output arrived after the last readyRead.
            output += process.readAllStandardOutput();
            // An earlier error (timeout, output cap, cancel) takes precedence over
            // whatever partial output exists.
            if (errorText.isEmpty()) {
                const auto data = QJsonDocument::fromJson(output).object();
                // Non-zero exit, a signal kill, or unparsable/empty JSON all mean the child
                // did not complete normally.
                if (code != 0 || status != QProcess::NormalExit || data.isEmpty())
                    errorText = "Calculation failed or exceeded its resource budget";
                else if (data.value("ok").toBool())
                    resultText = data.value("result").toString();
                else
                    errorText = data.value("error").toString();
            }
            emit changed();
        });
    }
    // Make sure no orphan Python process outlives the application window; the
    // 1 s wait bounds shutdown time.
    ~MathEngine() override { process.kill(); process.waitForFinished(1000); }
    /** True while the child process is starting or running (QML `busy`). */
    bool busy() const { return process.state() != QProcess::NotRunning; }
    /** Text of the last successful result; cleared by the next calculate() (QML `result`). */
    QString result() const { return resultText; }
    /** Message of the last failure, empty on success (QML `error`). */
    QString error() const { return errorText; }
    /**
     * Starts one calculation; ignored if one is already running.
     *
     * @param expression Maths text, e.g. "(x + 1)**3" (validated by the script).
     * @param operation  Exact operation name from the dialog's drop-down, such as
     *                   "Simplify" or "Differentiate".
     * @param variable   Symbol for calculus/solve operations, normally "x".
     * Results arrive asynchronously via `changed`; this call never blocks.
     */
    Q_INVOKABLE void calculate(const QString &expression, const QString &operation, const QString &variable) {
        // A second request while one runs would clobber the shared buffers.
        if (busy()) return;
        // Reset per-run state so a previous result or error is never shown for the
        // new request.
        resultText.clear(); errorText.clear(); output.clear();
        // Compact JSON keeps the request tiny (the script rejects > 8 KiB).
        request = QJsonDocument(QJsonObject{{"expression", expression}, {"operation", operation}, {"variable", variable}}).toJson(QJsonDocument::Compact);
        // "-I" is Python's isolated mode: ignores PYTHON* environment variables and
        // the working directory, so only the vetted script and installed packages run.
        process.start(QStringLiteral(ARCHI_MATH_PYTHON), {"-I", QStringLiteral(ARCHI_MATH_SCRIPT)});
        // 6000 ms budget; keep in step with the script's 4 s CPU limit.
        timer.start(6000);
        emit changed();
    }
    /**
     * Aborts the running calculation (QML "Cancel" button); no-op when idle.
     * Sets the error to "Cancelled" before killing so the `finished` handler
     * keeps that message.
     */
    Q_INVOKABLE void cancel() {
        if (!busy()) return;
        errorText = "Cancelled";
        timer.stop();
        process.kill();
    }
/** Emitted whenever busy, result or error may have changed. */
signals:
    void changed();
};
