QT += core gui qml quick quickcontrols2 dbus network

CONFIG += c++17 release
TARGET = zephyr
TEMPLATE = app

INCLUDEPATH += /usr/include/LayerShellQt
LIBS += -lLayerShellQtInterface

HEADERS += \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc

HEADERS += src/backend.h
SOURCES += src/backend.cpp
