#include <QGuiApplication>
#include <QFontDatabase>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>
#include <QLockFile>
#include <QLocalServer>
#include <QLocalSocket>
#include <QStandardPaths>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTextStream>
#include <LayerShellQt/window.h>
#include "backend.h"
#include "theme.h"
#include "translator.h"
int main(int argc,char **argv){
 QStringList args;for(int i=1;i<argc;++i)args<<QString::fromLocal8Bit(argv[i]);
 const bool shot=args.contains("--screenshot"),status=args.contains("status"),apply=args.value(0)=="set",listControls=args.value(0)=="controls";
 if(shot||status||apply||listControls){qputenv("QT_QPA_PLATFORM","offscreen");qputenv("QT_QPA_PLATFORMTHEME","generic");}
 // Set the app ID before QGuiApplication exists: Qt registers it with the desktop portal during
 // start-up, and the platform theme talks to the portal first if the ID comes later.
 QGuiApplication::setDesktopFileName("rog-companion");
 QGuiApplication app(argc,argv);app.setApplicationName("rog-companion");app.setApplicationVersion("0.3.2");
 QQuickStyle::setStyle("Material");
 // Inter ships inside the binary (SIL OFL, see src/fonts/Inter-OFL.txt), so the panel looks the same on every
 // system. Numbers use the user's own monospace font, which is where the Linux personality comes from.
 QString uiFont="sans-serif";
 {const int id=QFontDatabase::addApplicationFont(":/fonts/InterVariable.ttf");
  if(id>=0&&!QFontDatabase::applicationFontFamilies(id).isEmpty())uiFont=QFontDatabase::applicationFontFamilies(id).first();}
 const bool gui=!shot&&!status&&!apply&&!listControls;
 const QString ipcPath=QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)+"/rog-companion-control";
 QLockFile lock(ipcPath+".lock");lock.setStaleLockTime(0);
 // A panel is already running: ask it to open its controls and leave, before reading any hardware.
 if(gui&&!lock.tryLock()){QLocalSocket socket;socket.connectToServer(ipcPath);if(socket.waitForConnected(1000)){socket.write("open");socket.waitForBytesWritten(1000);return 0;}QTextStream(stderr)<<"ROG Companion is running but its control socket is unavailable.\n";return 1;}
 Backend backend;
 if(apply){
  if(args.size()<3){QTextStream(stderr)<<"Usage: rog-companion set CONTROL VALUE --json\n";return 1;}
  QObject::connect(&backend,&Backend::controlFinished,&app,[&](bool ok){
   QTextStream(stdout)<<QJsonDocument(QJsonObject{{"ok",ok},{"message",backend.message()},{"state",QJsonObject::fromVariantMap(backend.state())}}).toJson();
   app.exit(ok?0:1);
  });
  QObject::connect(&backend,&Backend::discoveryFinished,&app,[&]{backend.setControl(args[1],args[2]);},Qt::SingleShotConnection);
  return app.exec();
 }
 // Every control with whether it's available here and why not: what testers paste into bug reports.
 if(listControls){QObject::connect(&backend,&Backend::discoveryFinished,&app,[&]{QJsonArray out;
  for(const auto &v:backend.controls()){const auto c=v.toMap();QJsonObject o{{"id",c["id"].toString()},{"label",c["label"].toString()},{"group",c["group"].toString()},{"available",c["available"].toBool()},{"value",QJsonValue::fromVariant(c["value"])}};
   if(!c["available"].toBool())o["reason"]=c["reason"].toString();
   out<<o;}
  QTextStream(stdout)<<QJsonDocument(out).toJson();app.quit();});return app.exec();}
 if(status){QTimer::singleShot(1200,&app,[&]{auto s=backend.state();QTextStream(stdout)<<QJsonDocument(QJsonObject::fromVariantMap(s)).toJson();app.quit();});return app.exec();}
 Theme theme;Translator translator(args.contains("--language-test")?args.value(args.indexOf("--language-test")+1):QString());app.installTranslator(&translator);
 QQmlApplicationEngine engine;QObject::connect(&translator,&Translator::changed,&engine,&QQmlEngine::retranslate);
 engine.rootContext()->setContextProperty("backend",&backend);engine.rootContext()->setContextProperty("theme",&theme);engine.rootContext()->setContextProperty("translator",&translator);engine.rootContext()->setContextProperty("uiFont",uiFont);
 engine.load(QUrl("qrc:/Main.qml"));if(engine.rootObjects().isEmpty())return 1;
 auto *window=qobject_cast<QQuickWindow*>(engine.rootObjects().first());if(!window)return 1;backend.attachWindow(window);
 if(QGuiApplication::platformName()=="wayland"){
  auto*layer=LayerShellQt::Window::get(window);layer->setScope("rog-companion");layer->setLayer(LayerShellQt::Window::LayerBottom);
  layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorRight)|LayerShellQt::Window::AnchorBottom);layer->setMargins(QMargins(18,42,18,18));layer->setExclusiveZone(0);
  layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);layer->setActivateOnShow(false);
  for(auto*screen:app.screens())if(screen->name().startsWith("eDP")){layer->setScreen(screen);window->setScreen(screen);break;}
 }
 QLocalServer server;
 if(!shot){QLocalServer::removeServer(ipcPath);server.setSocketOptions(QLocalServer::UserAccessOption);server.listen(ipcPath);
 QObject::connect(&server,&QLocalServer::newConnection,&app,[&]{auto*client=server.nextPendingConnection();QObject::connect(client,&QLocalSocket::readyRead,&app,[&,client]{client->readAll();window->setProperty("expanded",true);backend.raisePanel(true);client->disconnectFromServer();});QObject::connect(client,&QLocalSocket::disconnected,client,&QObject::deleteLater);});}
 window->show();
 if(shot&&args.contains("--expanded"))window->setProperty("expanded",true);  // README screenshot of the controls
 if(shot&&args.contains("--tab"))window->setProperty("selectedTab",args.value(args.indexOf("--tab")+1).toInt());
 if(shot&&args.contains("--dialog"))QTimer::singleShot(600,window,[window,name=args.value(args.indexOf("--dialog")+1)]{QMetaObject::invokeMethod(window,"showDialog",Q_ARG(QVariant,name));});
 if(shot){int i=args.indexOf("--screenshot");QString path=args.value(i+1,"/tmp/rog-companion.png");QTimer::singleShot(2200,&app,[&,path]{bool ok=window->grabWindow().save(path);QTextStream(stdout)<<(ok?"Saved ":"Failed ")<<path<<"\n";app.exit(ok?0:1);});}
 return app.exec();
}
