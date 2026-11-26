#include "backend.h"
#include <QCoreApplication>
#include <QGuiApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QWindow>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <memory>
#include <LayerShellQt/window.h>
#include <cmath>
#include <algorithm>

namespace {
const QString fw="/sys/class/firmware-attributes/asus-armoury/attributes/";
QString home(){return QDir::homePath();}
// Settings live here. Earlier releases were called Zephyr; their policy file is moved over once.
QString stateDir(){
 const QString dir=home()+"/.local/state/rog-companion",old=home()+"/.local/state/zephyr";
 if(!QFileInfo::exists(dir+"/policy.json")&&QFileInfo::exists(old+"/policy.json")){QDir().mkpath(dir);QFile::copy(old+"/policy.json",dir+"/policy.json");}
 return dir;
}
QVariant number(const QString &path,double scale=1) {bool ok=false;double n=Backend::readFile(path).toDouble(&ok);return ok?QVariant(n/scale):QVariant();}
QVariantList options(std::initializer_list<std::pair<QString,QString>> pairs){QVariantList a;for(auto &p:pairs)a<<QVariantMap{{"label",p.first},{"value",p.second}};return a;}
QString capture(const QString&s,const QString&key){return QRegularExpression("\\b"+key+":\\s*([^,\\n]+)").match(s).captured(1).trimmed();}
QString activeAuraColour(const QString &aura,const QString &mode) {
 const auto block=QRegularExpression("\\b"+QRegularExpression::escape(mode)+
     ":\\s*\\([\\s\\S]*?colour1:\\s*\\(([^)]*)\\)").match(aura);
 if(!block.hasMatch())return {};
 QString colour;
 for(const auto &channel:QStringList{"r","g","b"}) {
  bool ok=false;const int value=capture(block.captured(1),channel).toInt(&ok);
  if(!ok||value<0||value>255)return {};
  colour+=QString::number(value,16).rightJustified(2,'0');
 }
 return colour;
}

}
QString Backend::readFile(const QString&p){QFile f(p);if(!f.open(QIODevice::ReadOnly))return {};return QString::fromUtf8(f.readAll()).trimmed();}
QString Backend::armoury(const QString&n)const{return readFile(fw+n+"/current_value");}
Backend::Backend(QObject*p,bool start):QObject(p){
 m_timeout.setSingleShot(true);m_timeout.setInterval(10000);
 connect(&m_timeout,&QTimer::timeout,this,[this]{m_commandTimedOut=true;m_process.kill();});
 connect(&m_process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError e){if(e==QProcess::FailedToStart)complete(false,m_process.errorString());});
 connect(&m_process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus s){
  if(!m_busy)return;
  m_timeout.stop();QString out=QString::fromUtf8(m_process.readAllStandardOutput());QString err=QString::fromUtf8(m_process.readAllStandardError());
  if(m_commandTimedOut){complete(false,tr("The control service did not respond within 10 seconds."));return;}
  m_output+=out;const bool reportedError=QRegularExpression("(?:\\[ERROR|Error:|failed to|org\\.freedesktop\\.DBus\\.Error)",QRegularExpression::CaseInsensitiveOption).match(out+err).hasMatch();if(code||s!=QProcess::NormalExit||reportedError){complete(false,(err+out).trimmed());return;}step();
 });
 m_gpuTimeout.setSingleShot(true);m_gpuTimeout.setInterval(3000);
 connect(&m_gpuTimeout,&QTimer::timeout,this,[this]{m_gpuProcess.kill();});
 connect(&m_gpuProcess,&QProcess::errorOccurred,this,[this](QProcess::ProcessError error){
  if(error==QProcess::FailedToStart)m_gpuTimeout.stop();
 });
 connect(&m_gpuProcess,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus exitStatus){
  m_gpuTimeout.stop();const QString output=QString::fromUtf8(m_gpuProcess.readAllStandardOutput()).trimmed();
  m_gpuProcess.readAllStandardError();
  if(code==0&&exitStatus==QProcess::NormalExit&&readFile(m_gpuRuntimeFile)=="active") {
   const auto fields=output.section('\n',0,0).split(',');
   if(fields.size()==3) {
    QVariantMap sample;
    const QStringList keys{"gpuTemp","gpuPower","gpuUtilization"};
    for(int i=0;i<3;++i) {bool ok=false;const double value=fields[i].trimmed().toDouble(&ok);
     sample[keys[i]]=ok&&std::isfinite(value)&&value>=0?QVariant(value):QVariant();}
    m_gpuSample=sample;m_gpuSampleAt=QDateTime::currentMSecsSinceEpoch();
   }
  }
  readState();
 });
 connect(&m_poll,&QTimer::timeout,this,&Backend::readState);m_poll.setInterval(5000);
 if(start){m_panelRates=panelRates();readState();QTimer::singleShot(0,this,&Backend::discover);m_poll.start();}
}
QList<int> Backend::panelRates(){
 QProcess hyprctl;hyprctl.start("hyprctl",{"monitors","-j"});
 if(!hyprctl.waitForFinished(2000))return {};
 QList<int> rates;
 for(const auto &m:QJsonDocument::fromJson(hyprctl.readAllStandardOutput()).array()){
  const auto o=m.toObject();if(!o["name"].toString().startsWith("eDP-"))continue;
  const QString prefix=QString("%1x%2@").arg(o["width"].toInt()).arg(o["height"].toInt());
  for(const auto &mode:o["availableModes"].toArray()){const QString s=mode.toString();
   if(s.startsWith(prefix)){const int r=qRound(s.mid(prefix.size()).chopped(2).toDouble());if(r>0&&!rates.contains(r))rates<<r;}}
  break;
 }
 std::sort(rates.begin(),rates.end());return rates;
}
// Destroying a running QProcess kills it and emits finished(). Our handlers would then call
// readState() on a half-destroyed Backend, so cut them off before any member is torn down.
Backend::~Backend(){
 m_poll.stop();m_timeout.stop();m_gpuTimeout.stop();
 m_process.disconnect();m_gpuProcess.disconnect();
 // Stop children ourselves so Qt doesn't warn about destroying a running process.
 for(QProcess *p:{&m_process,&m_gpuProcess})if(p->state()!=QProcess::NotRunning){p->kill();p->waitForFinished(500);}
}
void Backend::setMessage(const QString&s){m_message=s;emit messageChanged();}
void Backend::execute(const QList<Command>&cmds,std::function<void(bool,QString)>done){
 if(m_busy){setMessage(tr("Wait for the current operation to finish."));return;}
 m_busy=true;emit busyChanged();m_output.clear();m_queue.clear();for(const auto&c:cmds)m_queue.enqueue(c);m_done=done;step();
}
void Backend::step(){if(m_queue.isEmpty()){complete(true,m_output.trimmed());return;}auto c=m_queue.dequeue();m_commandTimedOut=false;m_process.start(c.program,c.args);m_timeout.start();}
void Backend::complete(bool ok,const QString&out){m_timeout.stop();m_queue.clear();m_busy=false;emit busyChanged();auto cb=std::move(m_done);m_done={};if(cb)cb(ok,out);}
QVariantMap Backend::policy()const{QFile f(stateDir()+"/policy.json");if(!f.open(QIODevice::ReadOnly))return {};return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();}
bool Backend::savePolicy(const QString&key,const QVariant&v){auto d=policy();d[key]=v;QDir().mkpath(stateDir());QSaveFile f(stateDir()+"/policy.json");if(!f.open(QIODevice::WriteOnly))return false;f.write(QJsonDocument(QJsonObject::fromVariantMap(d)).toJson());return f.commit();}
void Backend::readState(){
 QVariantMap s;
 s["model"]=readFile("/sys/class/dmi/id/product_name");s["updated"]=QDateTime::currentDateTime().toString("HH:mm:ss");
 s["ac"]=false;
 m_battery.clear();
 QDir power("/sys/class/power_supply");for(const auto&name:power.entryList(QDir::Dirs|QDir::NoDotAndDotDot)){
  const QString p=power.filePath(name);if(readFile(p+"/type")=="Battery"){
   if(readFile(p+"/scope")!="Device" && (m_battery.isEmpty() || (!QFileInfo::exists(m_battery+"/charge_control_end_threshold") && QFileInfo::exists(p+"/charge_control_end_threshold"))))m_battery=p;
  }
  else if(readFile(p+"/online")=="1")s["ac"]=true;
 }
 s["battery"]=number(m_battery+"/capacity");s["batteryStatus"]=readFile(m_battery+"/status");
 auto full=number(m_battery+"/charge_full"),design=number(m_battery+"/charge_full_design");
 if(!full.isValid()){full=number(m_battery+"/energy_full");design=number(m_battery+"/energy_full_design");}
 s["batteryHealth"]=(full.isValid()&&design.toDouble()>0)?QVariant(100*full.toDouble()/design.toDouble()):QVariant();
 s["watts"]=number(m_battery+"/power_now",1e6);
 if(!s["watts"].isValid()){auto i=number(m_battery+"/current_now",1e6),v=number(m_battery+"/voltage_now",1e6);if(i.isValid()&&v.isValid())s["watts"]=i.toDouble()*v.toDouble();}
 s["chargeLimit"]=number(m_battery+"/charge_control_end_threshold");
 // Read PCI runtime state before touching NVIDIA telemetry: sleeping GPUs stay asleep.
 m_gpuRuntimeFile.clear();
 const QDir pci("/sys/bus/pci/devices");
 for(const auto &device:pci.entryList(QDir::Dirs|QDir::NoDotAndDotDot)) {
  const QString path=pci.filePath(device);
  if(readFile(path+"/vendor")=="0x10de"&&readFile(path+"/class").startsWith("0x03")) {
   m_gpuRuntimeFile=path+"/power/runtime_status";break;
  }
 }
 const bool gpuAwake=!m_gpuRuntimeFile.isEmpty()&&readFile(m_gpuRuntimeFile)=="active";
 const qint64 now=QDateTime::currentMSecsSinceEpoch();
 s["gpuAwake"]=gpuAwake;s["gpuPower"]=QVariant();s["gpuUtilization"]=QVariant();
 if(!gpuAwake) {
  m_gpuSample.clear();m_gpuSampleAt=0;
  if(m_gpuProcess.state()!=QProcess::NotRunning)m_gpuProcess.kill();
 } else if(m_gpuProcess.state()==QProcess::NotRunning&&(m_gpuQueryAt==0||now-m_gpuQueryAt>=30000)) {
  m_gpuQueryAt=now;
  // Recheck immediately before launch, and query only the already-active display GPU.
  if(readFile(m_gpuRuntimeFile)=="active"&&!QStandardPaths::findExecutable("nvidia-smi").isEmpty()) {
   QDir gpuDirectory=QFileInfo(m_gpuRuntimeFile).dir();gpuDirectory.cdUp();
   const QString busId=gpuDirectory.dirName();
   m_gpuProcess.start("nvidia-smi",{"--id="+busId,"--query-gpu=temperature.gpu,power.draw,utilization.gpu","--format=csv,noheader,nounits"});
   m_gpuTimeout.start();
  }
 }
 s["cpuTemp"]=QVariant();s["gpuTemp"]=QVariant();s["fanCpu"]=QVariant();s["fanGpu"]=QVariant();s["fanMid"]=QVariant();
 m_fanCurves.clear();
 QDir hw("/sys/class/hwmon");for(const auto&name:hw.entryList(QDir::Dirs|QDir::NoDotAndDotDot)){
  auto p=hw.filePath(name);auto kind=readFile(p+"/name");
  if(kind=="k10temp")s["cpuTemp"]=number(p+"/temp1_input",1000);
  if(gpuAwake&&kind.startsWith("nvidia"))s["gpuTemp"]=number(p+"/temp1_input",1000);
  if(kind=="asus_custom_fan_curve") {
   for(int fan=1;fan<=3;++fan) {
    QStringList points;
    for(int point=1;point<=8;++point) {
     const auto stem=p+QString("/pwm%1_auto_point%2_").arg(fan).arg(point);
     const auto temp=number(stem+"temp"),pwm=number(stem+"pwm");
     if(!temp.isValid()||!pwm.isValid())break;
     points<<QString("%1c:%2%").arg(temp.toInt()).arg(qRound(pwm.toDouble()*100/255));
    }
    const QString key=QStringList{"cpu","gpu","mid"}[fan-1];
    m_fanCurves[key]=points.size()==8?points.join(','):QString();
    m_fanCurves[key+"Enabled"]=readFile(p+QString("/pwm%1_enable").arg(fan))=="1";
   }
  }
  if(kind=="asus") {s["fanCpu"]=number(p+"/fan1_input");s["fanGpu"]=number(p+"/fan2_input");s["fanMid"]=number(p+"/fan3_input");}
 }
 if(gpuAwake&&m_gpuSampleAt>0&&now-m_gpuSampleAt<=35000) {
  for(const auto &key:QStringList{"gpuTemp","gpuPower","gpuUtilization"})
   if(m_gpuSample.value(key).isValid())s[key]=m_gpuSample.value(key);
 }
 auto platform=readFile("/sys/firmware/acpi/platform_profile");s["profile"]=platform=="quiet"?"Quiet":platform=="balanced"?"Balanced":platform=="performance"?"Performance":platform;
 if(!s["profile"].toString().isEmpty())m_fanProfile=s["profile"].toString();
 auto mux=armoury("gpu_mux_mode"),disabled=armoury("dgpu_disable");
 s["gpuMode"]=mux=="0"?"NVIDIA only":disabled=="1"?"Integrated":"Hybrid";
 if(mux.isEmpty())s["gpuMode"]="Unavailable";
 s["pendingGpu"]=m_pendingGpu;s["gpuQueueKnown"]=m_gpuQueueKnown;
 s["error"]="";m_state=s;buildControls();emit changed();
 requestQueuedGpu();
}
// The queued GPU mode lives in asusd. Ask asynchronously: a hung daemon must never freeze the panel,
// and this runs on every poll.
void Backend::requestQueuedGpu(std::function<void(bool)> after){
 // Keep the follow-up on the object: a poll that supersedes this request must still deliver it.
 if(after)m_afterGpu=std::move(after);
 const int generation=++m_gpuGeneration;
 auto results=std::make_shared<QVariantMap>();
 auto remaining=std::make_shared<int>(2);
 for(const QString attribute:{"gpu_mux_mode","dgpu_disable"}) {
  auto request=QDBusMessage::createMethodCall("xyz.ljones.Asusd","/xyz/ljones/asus_armoury/"+attribute,
      "org.freedesktop.DBus.Properties","Get");
  request<<"xyz.ljones.AsusArmoury"<<"QueuedGpuValue";
  auto *watcher=new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(request,1000),this);
  connect(watcher,&QDBusPendingCallWatcher::finished,this,[this,generation,results,remaining,attribute](QDBusPendingCallWatcher *w){
   QDBusPendingReply<QDBusVariant> reply=*w;w->deleteLater();
   if(!reply.isError())(*results)[attribute]=reply.value().variant();
   if(--*remaining>0)return;
   // A newer request supersedes this one, so a slow old answer can't overwrite fresh state.
   if(generation!=m_gpuGeneration)return;
   applyQueuedGpu(*results);
   if(m_afterGpu){auto done=std::move(m_afterGpu);m_afterGpu={};done(m_gpuQueueKnown);}
  });
 }
}
void Backend::applyQueuedGpu(const QVariantMap &queued){
 // QueuedGpuValue is daemon state, not a claim that routing already changed.
 const auto queuedMux=queued.value("gpu_mux_mode"),queuedDisable=queued.value("dgpu_disable");

 auto resolve=[](const QVariant &queued,const QString &current,bool &known){
  bool ok=false;
  int target=queued.toInt(&ok);
  if(ok && target==-1)target=current.toInt(&ok);
  known=ok && (target==0 || target==1);
  return target;
 };
 bool muxKnown=false,disableKnown=false;
 const int mux=resolve(queuedMux,armoury("gpu_mux_mode"),muxKnown);
 const int disabled=resolve(queuedDisable,armoury("dgpu_disable"),disableKnown);
 const bool known=muxKnown && disableKnown;
 QString pending;
 if(known && (queuedMux.toInt()>=0 || queuedDisable.toInt()>=0))
  pending=mux==0?"ultimate":disabled==1?"integrated":"hybrid";
 if(pending==m_pendingGpu && known==m_gpuQueueKnown)return;
 m_pendingGpu=pending;m_gpuQueueKnown=known;
 m_state["pendingGpu"]=pending;m_state["gpuQueueKnown"]=known;
 buildControls();emit changed();
}
void Backend::discover(){
 m_serviceFans.clear();
 m_asusAvailable=!QStandardPaths::findExecutable("asusctl").isEmpty();m_ppAvailable=!QStandardPaths::findExecutable("powerprofilesctl").isEmpty();
 if(!m_asusAvailable){setMessage(tr("asusctl is missing; ASUS controls are unavailable."));buildControls();emit discoveryFinished();return;}
 execute({{"asusctl",{"fan-curve","--mod-profile",m_fanProfile}}},[this](bool ok,QString out){
  if(ok){
   static const QRegularExpression fanPattern(R"(fan:\s*(cpu|gpu|mid)\b)",QRegularExpression::CaseInsensitiveOption);
   auto matches=fanPattern.globalMatch(out);
   while(matches.hasNext())m_serviceFans.append(matches.next().captured(1).toLower());
  }else setMessage(tr("Fan service unavailable: %1").arg(out));
  buildControls();emit discoveryFinished();
 });
}
void Backend::refresh(){if(m_busy)return;m_panelRates=panelRates();readState();discover();}
QVariantMap Backend::control(const QString&id)const{for(const auto&v:m_controls){auto c=v.toMap();if(c["id"]==id)return c;}return {};}
bool Backend::validChoice(const QVariantMap&c,const QVariant&v){for(const auto&o:c["options"].toList())if(o.toMap()["value"].toString()==v.toString())return true;return false;}
void Backend::buildControls(){
 QVariantList list;
 auto add=[&](QString id,QString label,QString group,QString kind,QVariant val,bool available=true,QString reason=QString(),bool confirm=false,QString description=QString()) -> QVariantMap {
  return {{"id",id},{"label",label},{"group",group},{"kind",kind},{"value",val},{"available",available},{"reason",reason},{"confirm",confirm},{"description",description}};
 };
 auto choice=[&](QString id,QString label,QString group,QVariant val,QVariantList opts,bool avail=true,bool confirm=false,QString desc=QString()){auto c=add(id,label,group,"choice",val,avail,avail?"":tr("Not exposed by this device or its driver."),confirm,desc);c["options"]=opts;list<<c;};
 auto numeric=[&](QString id,QString label,QString group,QVariant val,int min,int max,QString unit,bool available=true){auto c=add(id,label,group,"number",val,available,available?"":tr("Not exposed by firmware."));c["min"]=min;c["max"]=max;c["step"]=1;c["unit"]=unit;list<<c;};
 QString pp=readFile("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference");
 QString profile=m_state["profile"].toString();
 choice("profile",tr("Performance mode"),"Power",profile,options({{tr("Silent"),"Quiet"},{tr("Balanced"),"Balanced"},{tr("Turbo"),"Performance"}}),m_asusAvailable,false,tr("Firmware fan and power preset. Battery automation takes over at the next power-source change."));
 auto pol=policy();
 auto profiles=options({{tr("Power saver"),"power-saver"},{tr("Balanced"),"balanced"},{tr("Performance"),"performance"}});
 choice("batteryProfile",tr("When unplugged"),"Power",pol.value("batteryProfile","power-saver"),profiles);
 choice("acProfile",tr("When plugged in"),"Power",pol.value("acProfile","performance"),profiles);
 numeric("charge",tr("Charge ceiling"),"Power",m_state["chargeLimit"],20,100,"%",m_asusAvailable&&m_state["chargeLimit"].isValid());
 list<<add("oneshot",tr("Charge to 100% once"),"Power","action",true,m_asusAvailable,{},true,tr("Temporarily charge fully; ASUS restores the configured ceiling afterward."));
 list<<add("boost",tr("CPU turbo boost"),"Power","toggle",readFile("/sys/devices/system/cpu/cpufreq/boost")=="1",QFileInfo::exists("/sys/devices/system/cpu/cpufreq/boost"),{},true,tr("Requires system authentication. Disabling boost reduces peak performance and heat until reboot."));
 choice("gpu",tr("Graphics mode"),"Power",armoury("gpu_mux_mode")=="0"?"ultimate":armoury("dgpu_disable")=="1"?"integrated":"hybrid",options({{tr("Hybrid"),"hybrid"},{tr("Integrated / Eco"),"integrated"},{tr("NVIDIA / Ultimate"),"ultimate"}}),m_asusAvailable&&!armoury("gpu_mux_mode").isEmpty()&&!armoury("dgpu_disable").isEmpty(),true,tr("Queued by ASUS for reboot. Eco can disable NVIDIA-wired HDMI. Save work before rebooting. Current pending request: %1").arg(!m_gpuQueueKnown?tr("unknown"):m_pendingGpu.isEmpty()?tr("none queued"):m_pendingGpu));
 for(const auto&attr:QStringList{"ppt_pl1_spl","ppt_pl2_sppt","ppt_pl3_fppt","nv_tgp","nv_dynamic_boost","nv_temp_target"}){
  const QMap<QString,QString> labels{{"ppt_pl1_spl",tr("CPU sustained power")},{"ppt_pl2_sppt",tr("CPU short boost power")},{"ppt_pl3_fppt",tr("CPU fast boost power")},{"nv_tgp",tr("GPU power limit")},{"nv_dynamic_boost",tr("GPU Dynamic Boost")},{"nv_temp_target",tr("GPU temperature target")}};
  if(!QFileInfo::exists(fw+attr))continue;  // this model has no such limit: don't show it at all
  // Limits are shown read-only: writing power limits is left to firmware tools until it's tested per model.
  const auto value=number(fw+attr+"/current_value"),low=number(fw+attr+"/min_value"),high=number(fw+attr+"/max_value");
  if(!value.isValid())continue;  // listed by firmware but unreadable (e.g. the GA403UP): nothing useful to show
  auto c=add("limit_"+attr,labels[attr],"Power","number",value,false,
     tr("Shown for reference. ROG Companion doesn't change firmware power limits yet."));
  c["min"]=low.isValid()?low.toInt():0;c["max"]=high.isValid()?high.toInt():qMax(100,value.toInt());c["step"]=1;c["unit"]=attr=="nv_temp_target"?"°C":"W";list<<c;
 }
 m_fansAvailable=false;
 for(const auto&fan:QStringList{"cpu","gpu","mid"}){
  const bool available=m_asusAvailable && (m_serviceFans.contains(fan)||!m_fanCurves.value(fan).toString().isEmpty());
  m_fansAvailable |= available;
  auto c=add("fan_"+fan,tr("%1 fan curve").arg(fan.toUpper()),"Fans","text","",available, tr("ASUS fan service is unavailable."),true,tr("%1 profile. Eight increasing temperature points, 0–100% speed. Example: 30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:100%. Apply saves and enables this fan curve.").arg(m_fanProfile));
  c["value"]=m_fanCurves.value(fan);list<<c;
 }
 list<<add("fan_default",tr("Restore firmware fan curves"),"Fans","action",true,m_fansAvailable,{},true,tr("Restore default curves for the active profile."));
 list<<add("fan_enabled",tr("Custom fan curves"),"Fans","toggle",m_fanCurves.value("cpuEnabled").toBool()||m_fanCurves.value("gpuEnabled").toBool()||m_fanCurves.value("midEnabled").toBool(),m_fansAvailable,{},true,tr("Enable or disable all custom curves for the active profile."));
 m_backlight.clear();QDir bl("/sys/class/backlight");for(const auto&n:bl.entryList(QDir::Dirs|QDir::NoDotAndDotDot)){if(readFile(bl.filePath(n)+"/max_brightness").toInt()>0){m_backlight=n;break;}}
 double max=readFile(bl.filePath(m_backlight)+"/max_brightness").toDouble();numeric("brightness",tr("Display brightness"),"System",max>0?100*readFile(bl.filePath(m_backlight)+"/brightness").toDouble()/max:0,5,100,"%",!m_backlight.isEmpty());
 {
  QVariantList rates;
  if(m_panelRates.size()>1)rates<<QVariantMap{{"label",tr("Auto · %1/%2 Hz").arg(m_panelRates.first()).arg(m_panelRates.last())},{"value","auto"}};
  else rates<<QVariantMap{{"label",tr("Auto")},{"value","auto"}};
  for(int rate:m_panelRates)rates<<QVariantMap{{"label",tr("%1 Hz").arg(rate)},{"value",QString::number(rate)}};
  const QString refreshHelp=m_panelRates.size()>1
   ?tr("Auto uses %1 Hz on battery and %2 Hz plugged in. Applies within 30 seconds.").arg(m_panelRates.first()).arg(m_panelRates.last())
   :tr("Applied by the ROG Companion background service within 30 seconds.");
  choice("refreshMode",tr("Built-in display refresh"),"System",pol.value("refreshMode","auto"),rates,m_panelRates.size()>1,false,refreshHelp);
 }
 numeric("keyboard",tr("Keyboard brightness"),"Lighting",number("/sys/class/leds/asus::kbd_backlight/brightness"),0,3,"",QFileInfo::exists("/sys/class/leds/asus::kbd_backlight"));
 // asusd names the file after the keyboard's USB product id (aura_19b6.ron, aura_1866.ron, …).
 QString aura;{const auto files=QDir("/etc/asusd").entryList({"aura_*.ron"},QDir::Files,QDir::Name);if(!files.isEmpty())aura=readFile("/etc/asusd/"+files.first());}
 choice("aura",tr("Keyboard effect"),"Lighting",capture(aura,"current_mode").toLower(),options({{tr("Static"),"static"},{tr("Breathe"),"breathe"},{tr("Pulse"),"pulse"}}),m_asusAvailable&&!aura.isEmpty());
 auto color=add("color",tr("Keyboard colour"),"Lighting","text",activeAuraColour(aura,capture(aura,"current_mode")),m_asusAvailable&&!activeAuraColour(aura,capture(aura,"current_mode")).isEmpty(),{},false,tr("Six hexadecimal digits, e.g. ffd700. Applies a static colour."));list<<color;
 const auto keyboardState=QRegularExpression("zone:\\s*Keyboard\\s*,([^)]*)").match(aura).captured(1);
 for(const auto &flag:QStringList{"boot","awake","sleep","shutdown"}) {
  const QString id="keyboard"+flag.left(1).toUpper()+flag.mid(1);
  const QMap<QString,QString> labels{{"boot",tr("Keyboard at boot")},{"awake",tr("Keyboard while awake")},{"sleep",tr("Keyboard during sleep")},{"shutdown",tr("Keyboard at shutdown")}};
  list<<add(id,labels[flag],"Lighting","toggle",capture(keyboardState,flag)=="true",m_asusAvailable&&!keyboardState.isEmpty());
 }
 const QString slash=readFile("/etc/asusd/slash.ron");bool hasSlash=m_asusAvailable&&!slash.isEmpty();
 if(!slash.isEmpty()){  // only models with a Slash bar get these rows
 list<<add("slash",tr("Slash lighting"),"Lighting","toggle",capture(slash,"enabled")=="true",hasSlash);
 numeric("slashBrightness",tr("Slash brightness"),"Lighting",capture(slash,"brightness").toInt(),0,255,"",hasSlash);
 numeric("slashInterval",tr("Slash animation interval"),"Lighting",capture(slash,"display_interval").toInt(),0,5,"",hasSlash);
 list<<add("slashBatteryWarning",tr("Slash low battery warning"),"Lighting","toggle",capture(slash,"show_battery_warning")=="true",hasSlash);
 choice("slashMode",tr("Slash animation"),"Lighting",capture(slash,"display_mode").toLower(),options({{"Static","static"},{"Bounce","bounce"},{"Slash","slash"},{"Loading","loading"},{"Bit stream","bitstream"},{"Transmission","transmission"},{"Flow","flow"},{"Flux","flux"},{"Phantom","phantom"},{"Spectrum","spectrum"},{"Hazard","hazard"},{"Interfacing","interfacing"},{"Ramp","ramp"},{"Game over","gameover"},{"Start","start"},{"Buzzer","buzzer"}}),hasSlash);
 for(auto pair:QList<QPair<QString,QString>>{{"slashBattery","show_on_battery"},{"slashBoot","show_on_boot"},{"slashSleep","show_on_sleep"},{"slashShutdown","show_on_shutdown"}}){auto labels=QMap<QString,QString>{{"slashBattery",tr("Slash on battery")},{"slashBoot",tr("Slash at boot")},{"slashSleep",tr("Slash during sleep")},{"slashShutdown",tr("Slash at shutdown")}};list<<add(pair.first,labels[pair.first],"Lighting","toggle",capture(slash,pair.second)=="true",hasSlash);}
 }
 list<<add("bootSound",tr("Boot sound"),"System","toggle",armoury("boot_sound")=="1",!armoury("boot_sound").isEmpty());
 list<<add("lock",tr("Lock screen"),"System","action",true);
 list<<add("sleep",tr("Suspend"),"System","action",true,true,{},true,tr("The laptop will sleep. Save work first."));
 list<<add("reboot",tr("Restart computer"),"System","action",true,true,{},true,tr("Closes this session and applies queued GPU changes. Save all work first."));
 list<<add("shutdown",tr("Shut down"),"System","action",true,true,{},true,tr("Closes this session. Save all work first."));
 if(list!=m_controls){m_controls=list;emit controlsChanged();}
}
QString Backend::validateCurve(const QString&input){
 QStringList points=input.trimmed().split(',');if(points.size()!=8)return tr("Use exactly eight temperature:speed points.");int prevT=-1,prevP=-1;
 for(const auto&p:points){auto m=QRegularExpression("^\\s*(\\d{1,3})c:(\\d{1,3})%\\s*$").match(p);if(!m.hasMatch())return tr("Use the format 30c:10%,40c:20%,… with eight points.");int t=m.captured(1).toInt(),v=m.captured(2).toInt();if(t<0||t>110||v<0||v>100||t<=prevT||v<prevP)return tr("Temperatures must increase (0–110 °C); speeds must not decrease (0–100%).");prevT=t;prevP=v;}
 if(prevP!=100)return tr("The final fan point must reach 100% for cooling headroom.");
 return {};
}
void Backend::reportControl(bool ok,const QString &message){setMessage(message);emit controlFinished(ok);}
void Backend::setControl(const QString&id,const QVariant&value){
 if(m_busy){reportControl(false,tr("An operation is still running."));return;}auto c=control(id);if(c.isEmpty()||!c["available"].toBool()){reportControl(false,tr("This control is not available."));return;}
 auto kind=c["kind"].toString();if(kind=="choice"&&!validChoice(c,value)){reportControl(false,tr("Invalid selection."));return;}
 if(kind=="toggle" && value.toString()!="true" && value.toString()!="false"){reportControl(false,tr("Use true or false for this control."));return;}
 if(kind=="number"){bool ok;double d=value.toDouble(&ok);if(!ok||!std::isfinite(d)||d<c["min"].toDouble()||d>c["max"].toDouble()||std::floor(d)!=d){reportControl(false,tr("Value is outside the supported range."));return;}}
 QList<Command> cmds;QString v=value.toString();auto asus=[&](QStringList a){cmds.append(Command{"asusctl",a});};bool deferred=false;
 if(id=="profile")asus({"profile","set",v});
 else if(id=="batteryProfile"||id=="acProfile"||id=="refreshMode"){
  if(!savePolicy(id,value)){reportControl(false,tr("Unable to save automation policy."));return;}
  if(id!="refreshMode")asus({"profile","set",id=="batteryProfile"?"-b":"-a",v=="power-saver"?"Quiet":v=="balanced"?"Balanced":"Performance"});
  cmds.append(Command{"systemctl",{"--user","start","rog-companion-policy.service"}});
 } else if(id=="charge")asus({"battery","limit",QString::number(value.toInt())});
 else if(id=="oneshot")asus({"battery","oneshot","100"});
 else if(id=="boost")cmds.append(Command{"pkexec",{"/usr/lib/rog-companion/rog-companion-power-helper","boost",value.toBool()?"1":"0"}});
 else if(id=="gpu"){
  if(v=="ultimate"){asus({"armoury","set","dgpu_disable","0"});asus({"armoury","set","gpu_mux_mode","0"});}
  else{asus({"armoury","set","gpu_mux_mode","1"});asus({"armoury","set","dgpu_disable",v=="integrated"?"1":"0"});}deferred=true;
 }else if(id.startsWith("fan_")&&id!="fan_default"&&id!="fan_enabled"){
  auto error=validateCurve(v);if(!error.isEmpty()){reportControl(false,error);return;}
  v.remove(' ');asus({"fan-curve","--mod-profile",m_fanProfile,"--fan",id.mid(4),"--data",v});asus({"fan-curve","--mod-profile",m_fanProfile,"--fan",id.mid(4),"--enable-fan-curve","true"});
 }else if(id=="fan_default")asus({"fan-curve","--default"});
 else if(id=="fan_enabled")asus({"fan-curve","--mod-profile",m_fanProfile,"--enable-fan-curves",value.toBool()?"true":"false"});
 else if(id=="brightness")cmds.append(Command{"brightnessctl",{"--device",m_backlight,"set",QString::number(value.toInt())+"%"}});
 else if(id=="keyboard")asus({"leds","set",QStringList{"off","low","med","high"}[value.toInt()]});
 else if(id=="aura"){
  // Keep the user's colour when switching effects; gold is only the fallback when none is known.
  QString colour=control("color").value("value").toString();if(colour.isEmpty())colour="ffd700";
  if(v=="breathe")asus({"aura","effect",v,"-c",colour,"--colour2","111111"});else asus({"aura","effect",v,"-c",colour});}
 else if(id=="color"){if(!QRegularExpression("^[0-9a-fA-F]{6}$").match(v).hasMatch()){reportControl(false,tr("Enter six hexadecimal digits, without #."));return;}asus({"aura","effect","static","-c",v});}
 else if(id=="slash")asus({"slash","set",value.toBool()?"--enable":"--disable"});
 else if(id.startsWith("keyboard") && id!="keyboard"){
  QStringList a{"aura","power","keyboard"};for(const auto &pair:QList<QPair<QString,QString>>{{"keyboardBoot","--boot"},{"keyboardAwake","--awake"},{"keyboardSleep","--sleep"},{"keyboardShutdown","--shutdown"}}){bool on=pair.first==id?value.toBool():control(pair.first).value("value").toBool();if(on)a<<pair.second;}asus(a);
 }
 else if(id=="slashInterval")asus({"slash","set","--interval",QString::number(value.toInt())});
 else if(id=="slashBrightness")asus({"slash","set","--brightness",QString::number(value.toInt())});
 else if(id=="slashMode")asus({"slash","set","--mode",v});
 else if(id.startsWith("slash")){const QMap<QString,QString> flags{{"slashBattery","-b"},{"slashBoot","-B"},{"slashSleep","-s"},{"slashShutdown","-S"},{"slashBatteryWarning","-w"}};if(!flags.contains(id))return;asus({"slash","set",flags[id],value.toBool()?"true":"false"});}
 else if(id=="bootSound")asus({"armoury","set","boot_sound",value.toBool()?"1":"0"});
 else if(id=="lock"){if(!QStandardPaths::findExecutable("omarchy").isEmpty())cmds.append(Command{"omarchy",{"system","lock"}});else cmds.append(Command{"loginctl",{"lock-session"}});}
 else if(id=="sleep")cmds.append(Command{"systemctl",{"suspend"}});
 else if(id=="reboot")cmds.append(Command{"systemctl",{"reboot"}});
 else if(id=="shutdown")cmds.append(Command{"systemctl",{"poweroff"}});
 else{reportControl(false,tr("No handler exists for this control."));return;}
 setMessage(tr("Applying %1…").arg(c["label"].toString()));
 execute(cmds,[this,id,value,deferred](bool ok,QString out){
  if(!ok){readState();reportControl(false,tr("Could not apply: %1").arg(out));return;}
  readState();
  if(deferred){
   // Judge the result only once asusd has answered for the state after this write.
   setMessage(tr("Checking the queued graphics mode…"));
   requestQueuedGpu([this,value](bool fresh){
    if(!fresh){reportControl(false,tr("Graphics queue could not be read. Refresh to check."));return;}
    if(m_pendingGpu.isEmpty() && control("gpu").value("value")==value){reportControl(true,tr("Requested graphics mode is active. No restart is queued."));return;}
    if(m_pendingGpu==value.toString())reportControl(true,tr("Graphics request accepted by ASUS. Reboot required; current GPU routing has not changed."));
    else reportControl(false,tr("Command accepted; firmware has not confirmed the queued graphics mode. Refresh before retrying."));
   });
  } else if(id=="batteryProfile"||id=="acProfile"||id=="refreshMode"){
   reportControl(true,tr("Automation preference saved."));
  } else if(id=="oneshot") {
   const bool match=m_state["chargeLimit"].toInt()==100;reportControl(match,match?tr("Verified: one-shot charge ceiling is 100%."):tr("Command accepted; one-shot charge ceiling has not been confirmed."));
  } else if(id=="boost") {
   const bool match=readFile("/sys/devices/system/cpu/cpufreq/boost")== (value.toBool()?"1":"0");reportControl(match,match?tr("Verified: CPU boost updated."):tr("Readback mismatch: CPU boost did not match the request."));
  } else if(id.startsWith("fan_")||id=="lock"||id=="sleep"||id=="reboot"||id=="shutdown") {
   reportControl(true,tr("Command accepted. Status refreshed."));
  } else {
   const auto actual=control(id).value("value");
   bool match=actual.toString().compare(value.toString(),Qt::CaseInsensitive)==0;
   if(id=="brightness")match=std::abs(actual.toDouble()-value.toDouble())<=1.0;
   reportControl(match,match?tr("Verified: setting matches device readback."):tr("Readback mismatch: device has not confirmed the requested setting. Refresh to check."));
  }
  if(id.startsWith("fan_")||id=="profile")discover();
 });
}
void Backend::raisePanel(bool raised){auto*w=qobject_cast<QWindow*>(m_window);if(w&&QGuiApplication::platformName()=="wayland")LayerShellQt::Window::get(w)->setLayer(raised?LayerShellQt::Window::LayerTop:LayerShellQt::Window::LayerBottom);}
void Backend::quit(){QCoreApplication::quit();}
