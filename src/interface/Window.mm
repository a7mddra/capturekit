/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

#include "Window.h"
#include "DrawView.h"
#include <QApplication>
#include <QCloseEvent>
#include <QDebug>
#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>

static void DisplayReconfigurationCallBack(
    CGDirectDisplayID display,
    CGDisplayChangeSummaryFlags flags,
    void *userInfo)
{
    if (flags & kCGDisplayAddFlag || flags & kCGDisplayRemoveFlag) {
        qWarning() << "Display configuration changed! Exiting capturekit.";
        QApplication::exit(1);
    }
}

MainWindow::MainWindow(int displayNum, const QImage &bgImage, const QRect &geo, qreal dpr, QWidget *parent)
    : QMainWindow(parent), 
      m_displayNum(displayNum)
{
    m_drawView = new DrawView(bgImage, this);
    setCentralWidget(m_drawView);

    setWindowFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool | Qt::Popup);
    setAttribute(Qt::WA_ShowWithoutActivating);   
    setAttribute(Qt::WA_TranslucentBackground, false);
    
    setGeometry(geo);
    
    setContentsMargins(0, 0, 0, 0);
    m_drawView->setContentsMargins(0, 0, 0, 0);

    NSView *nsview = reinterpret_cast<NSView *>(winId());
    NSWindow *nswindow = [nsview window];
    [nswindow setAnimationBehavior: NSWindowAnimationBehaviorNone];
    [nswindow setHasShadow:NO];
    [nswindow setLevel:NSScreenSaverWindowLevel];

    CGError err = CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallBack, this);
    if (err != kCGErrorSuccess) {
        qWarning() << "Failed to register display reconfiguration callback:" << err;
    } else {
        qDebug() << "Successfully registered display reconfiguration callback.";
        m_displayChangeHandle = (void*)DisplayReconfigurationCallBack;
    }

    show();
}

MainWindow::~MainWindow()
{
    if (m_displayChangeHandle) {
        qDebug() << "Unregistering display reconfiguration callback.";
        CGDisplayRemoveReconfigurationCallback(DisplayReconfigurationCallBack, this);
    }
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    QApplication::exit(1);
    QMainWindow::closeEvent(event);
}
