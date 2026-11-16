#pragma once
#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QProcess>
#include <QTimer>
#include <QQueue>
#include <functional>

struct Command { QString program; QStringList args; };
class Backend : public QObject {
 Q_OBJECT
 Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
 Q_PROPERTY(QVariantList controls READ controls NOTIFY controlsChanged)
 Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
 Q_PROPERTY(QString message READ message NOTIFY messageChanged)
public:
 explicit Backend(QObject *parent=nullptr, bool start=true);
 QVariantMap state() const {return m_state;}
 QVariantList controls() const {return m_controls;}
 bool busy() const {return m_busy;}
 QString message() const {return m_message;}
 Q_INVOKABLE void refresh();
 Q_INVOKABLE void setControl(const QString &,const QVariant &);
 Q_INVOKABLE void raisePanel(bool raised);
 Q_INVOKABLE void quit();
 static QString validateCurve(const QString &input);
 static bool validChoice(const QVariantMap &control,const QVariant &value);
 static QString readFile(const QString &path);
 void setMessage(const QString &s);
 void attachWindow(QObject *w) {m_window=w;}
signals:
 void changed(); void controlsChanged(); void busyChanged(); void messageChanged();
private:
 void readState(); void buildControls(); void discover();
 void execute(const QList<Command> &,std::function<void(bool,QString)>);
 void step(); void complete(bool,const QString &);
 QVariantMap control(const QString&) const;
 bool savePolicy(const QString &,const QVariant&);
 QVariantMap policy() const;
 QString armoury(const QString &name) const;
 void requestQueuedGpu(std::function<void()> after={});
 void applyQueuedGpu(const QVariantMap &queued);
 static QList<int> panelRates(); QList<int> m_panelRates;
 int m_gpuGeneration=0; std::function<void()> m_afterGpu;
 QVariantMap m_state; QVariantList m_controls; QString m_message;
 bool m_busy=false; QTimer m_poll,m_timeout; QProcess m_process;
 QQueue<Command> m_queue; QString m_output; std::function<void(bool,QString)> m_done;
 QObject *m_window=nullptr; QString m_battery,m_backlight,m_fanProfile="Balanced";
 QVariantMap m_fanCurves; bool m_fansAvailable=false,m_asusAvailable=false,m_ppAvailable=false;
 QString m_pendingGpu;
 QProcess m_gpuProcess; QTimer m_gpuTimeout;
 QString m_gpuRuntimeFile; QVariantMap m_gpuSample;
 qint64 m_gpuQueryAt=0,m_gpuSampleAt=0;
};
