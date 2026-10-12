#pragma once
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>

class MathEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString result READ result NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    QProcess process;
    QTimer timer;
    QByteArray output;
    QByteArray request;
    QString resultText;
    QString errorText;
public:
    explicit MathEngine(QObject *parent = nullptr) : QObject(parent) {
        timer.setSingleShot(true);
        connect(&timer, &QTimer::timeout, this, [this] {
            errorText = "Calculation exceeded its time budget";
            process.kill();
        });
        connect(&process, &QProcess::started, this, [this] {
            process.write(request);
            process.closeWriteChannel();
            emit changed();
        });
        connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
            output += process.readAllStandardOutput();
            if (output.size() > 65536) {
                errorText = "Result exceeded its output budget";
                process.kill();
            }
        });
        connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                timer.stop();
                errorText = "Local math environment is unavailable";
                emit changed();
            }
        });
        connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
            timer.stop();
            output += process.readAllStandardOutput();
            if (errorText.isEmpty()) {
                const auto data = QJsonDocument::fromJson(output).object();
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
    ~MathEngine() override { process.kill(); process.waitForFinished(1000); }
    bool busy() const { return process.state() != QProcess::NotRunning; }
    QString result() const { return resultText; }
    QString error() const { return errorText; }
    Q_INVOKABLE void calculate(const QString &expression, const QString &operation, const QString &variable) {
        if (busy()) return;
        resultText.clear(); errorText.clear(); output.clear();
        request = QJsonDocument(QJsonObject{{"expression", expression}, {"operation", operation}, {"variable", variable}}).toJson(QJsonDocument::Compact);
        process.start(QStringLiteral(ARCHI_MATH_PYTHON), {"-I", QStringLiteral(ARCHI_MATH_SCRIPT)});
        timer.start(6000);
        emit changed();
    }
    Q_INVOKABLE void cancel() {
        if (!busy()) return;
        errorText = "Cancelled";
        timer.stop();
        process.kill();
    }
signals:
    void changed();
};
