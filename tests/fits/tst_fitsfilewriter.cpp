#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

#include "FitsFileWriter.h"

using namespace fits;

class TestFitsFileWriter : public QObject
{
    Q_OBJECT

private slots:
    void writeBytesWritesExactContentToLocalFile();
    void writeBytesToDirectoryJoinsDirectoryAndFileName();
    void writeBytesFailsForInvalidDirectory();
};

void TestFitsFileWriter::writeBytesWritesExactContentToLocalFile()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath("image.fits");
    const QByteArray data = QByteArrayLiteral("not really FITS, just bytes");

    FitsFileWriter writer;
    QVERIFY(writer.writeBytes(QUrl::fromLocalFile(path), data));
    QVERIFY(writer.lastError().isEmpty());

    QFile written(path);
    QVERIFY(written.open(QIODevice::ReadOnly));
    QCOMPARE(written.readAll(), data);
}

void TestFitsFileWriter::writeBytesToDirectoryJoinsDirectoryAndFileName()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QByteArray data = QByteArrayLiteral("autosaved bytes");

    FitsFileWriter writer;
    QVERIFY(writer.writeBytesToDirectory(QUrl::fromLocalFile(dir.path()), QStringLiteral("frame.fits"), data));

    QFile written(dir.filePath("frame.fits"));
    QVERIFY(written.open(QIODevice::ReadOnly));
    QCOMPARE(written.readAll(), data);
}

void TestFitsFileWriter::writeBytesFailsForInvalidDirectory()
{
    FitsFileWriter writer;
    // A non-existent parent directory - QFile::open() can't create it,
    // so this must fail cleanly with lastError set, not crash/assert.
    const bool ok = writer.writeBytesToDirectory(
        QUrl::fromLocalFile(QStringLiteral("/nonexistent-dir-for-test-xyz/also-missing")),
        QStringLiteral("frame.fits"), QByteArrayLiteral("data"));

    QVERIFY(!ok);
    QVERIFY(!writer.lastError().isEmpty());
}

QTEST_MAIN(TestFitsFileWriter)
#include "tst_fitsfilewriter.moc"
