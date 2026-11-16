QT += core gui testlib dbus
CONFIG += c++17 testcase
TARGET = zephyr_tests
TEMPLATE = app

INCLUDEPATH += ../src /usr/include/LayerShellQt
LIBS += -lLayerShellQtInterface

HEADERS += ../src/backend.h
SOURCES += zephyr_tests.cpp ../src/backend.cpp
