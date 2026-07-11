#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <qqmlintegration.h>

namespace fits {

// Writes a fetched FITS file's raw bytes (exactly as received over VFS -
// no re-encoding) to a local path chosen via QtQuick.Dialogs' FileDialog/
// FolderDialog, both of which hand QML a file:// QUrl rather than a plain
// path. Backs CameraView.qml's "Save to..."/"Auto-save" controls,
// mirroring datadisplaywidget.py's own save_data()/_on_new_data()
// auto-save path. A thin QObject rather than a free function purely
// because QML can only invoke methods on an object instance.
class FitsFileWriter : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit FitsFileWriter(QObject *parent = nullptr);

    QString lastError() const { return m_lastError; }

    // Writes `data` to `fileUrl` (a local file:// URL, e.g. FileDialog's
    // `selectedFile`). Returns success; lastError holds the message on
    // failure, cleared on success.
    Q_INVOKABLE bool writeBytes(const QUrl &fileUrl, const QByteArray &data);

    // Same, but joins `directoryUrl` (e.g. FolderDialog's
    // `selectedFolder`) with `fileName` first - the auto-save path, where
    // the destination filename comes from the module's own
    // NewImageEvent rather than a save dialog.
    Q_INVOKABLE bool writeBytesToDirectory(const QUrl &directoryUrl, const QString &fileName, const QByteArray &data);

Q_SIGNALS:
    void lastErrorChanged();

private:
    bool writeToLocalPath(const QString &path, const QByteArray &data);

    QString m_lastError;
};

} // namespace fits
