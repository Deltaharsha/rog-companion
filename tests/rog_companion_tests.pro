QT += core gui testlib dbus
CONFIG += c++17 testcase
TARGET = rog_companion_tests
TEMPLATE = app

INCLUDEPATH += ../src /usr/include/LayerShellQt
LIBS += -lLayerShellQtInterface

HEADERS += ../src/backend.h
SOURCES += rog_companion_tests.cpp ../src/backend.cpp
