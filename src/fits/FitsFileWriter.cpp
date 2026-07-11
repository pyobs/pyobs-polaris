#include "FitsFileWriter.h"

#include <QDir>
#include <QFile>

namespace fits {

FitsFileWriter::FitsFileWriter(QObject *parent)
    : QObject(parent)
{
}

bool FitsFileWriter::writeBytes(const QUrl &fileUrl, const QByteArray &data)
{
    return writeToLocalPath(fileUrl.toLocalFile(), data);
}

bool FitsFileWriter::writeBytesToDirectory(const QUrl &directoryUrl, const QString &fileName, const QByteArray &data)
{
    const QString dir = directoryUrl.toLocalFile();
    if (dir.isEmpty()) {
        m_lastError = QStringLiteral("Invalid directory.");
        Q_EMIT lastErrorChanged();
        return false;
    }
    return writeToLocalPath(QDir(dir).filePath(fileName), data);
}

bool FitsFileWriter::writeToLocalPath(const QString &path, const QByteArray &data)
{
    if (path.isEmpty()) {
        m_lastError = QStringLiteral("Invalid file path.");
        Q_EMIT lastErrorChanged();
        return false;
    }

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        m_lastError = file.errorString();
        Q_EMIT lastErrorChanged();
        return false;
    }
    if (file.write(data) != data.size()) {
        m_lastError = file.errorString();
        Q_EMIT lastErrorChanged();
        return false;
    }

    m_lastError.clear();
    Q_EMIT lastErrorChanged();
    return true;
}

} // namespace fits
