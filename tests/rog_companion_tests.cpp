#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"

class RogCompanionTests : public QObject {
    Q_OBJECT

private slots:
    void validFanCurveIsAccepted()
    {
        QCOMPARE(Backend::validateCurve(
                     "30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:100%"),
                 QString());
    }

    void malformedFanCurvesAreRejected()
    {
        const QString valid = "30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:100%";
        QVERIFY(!Backend::validateCurve("bad input").isEmpty());
        QVERIFY(!Backend::validateCurve("30:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:100%").isEmpty());

        auto points = valid.split(',');
        points.removeLast();
        QVERIFY(!Backend::validateCurve(points.join(',')).isEmpty()); // Seven points.
        points = valid.split(',');
        points.append("110c:100%");
        QVERIFY(!Backend::validateCurve(points.join(',')).isEmpty()); // Nine points.

        QVERIFY(!Backend::validateCurve(
                    "30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,80c:100%").isEmpty());
        QVERIFY(!Backend::validateCurve(
                    "30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:80%").isEmpty());
        QVERIFY(!Backend::validateCurve(
                    "30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:101%").isEmpty());
        QVERIFY(!Backend::validateCurve(
                    "30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,99c:99%").isEmpty());
    }

    void choiceMustMatchAnOfferedValue()
    {
        const QVariantMap control{{"options", QVariantList{
                                      QVariantMap{{"label", "Balanced"}, {"value", "balanced"}},
                                      QVariantMap{{"label", "Quiet"}, {"value", "quiet"}}}}};
        QVERIFY(Backend::validChoice(control, "balanced"));
        QVERIFY(Backend::validChoice(control, "quiet"));
        QVERIFY(!Backend::validChoice(control, "arbitrary-command"));
        QVERIFY(!Backend::validChoice(control, ""));
    }

    void readFileDistinguishesMissingFromZero()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QCOMPARE(Backend::readFile(dir.filePath("missing")), QString());
        QFile zero(dir.filePath("zero"));
        QVERIFY(zero.open(QIODevice::WriteOnly));
        QCOMPARE(zero.write("0\n"), qint64(2));
        zero.close();
        QCOMPARE(Backend::readFile(zero.fileName()), QString("0"));
    }

    void unavailableControlDoesNotRunACommand()
    {
        Backend backend(nullptr, false);
        QSignalSpy messageSpy(&backend, &Backend::messageChanged);
        backend.setControl("unknown-control", "value");
        QCOMPARE(backend.message(), QString("This control is not available."));
        QCOMPARE(messageSpy.count(), 1);
        QVERIFY(!backend.busy());
    }
};

QTEST_GUILESS_MAIN(RogCompanionTests)
#include "rog_companion_tests.moc"
