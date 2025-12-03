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
#include <QWindow>
// REMOVED: #include <QNativeInterface> (Included via QWindow)
#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>

// Static Callback for macOS Display Changes
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

MainWindow::MainWindow(int displayNum, const QImage &bgImage, const QRect &geo, QWidget *parent)
    : QMainWindow(parent), 
      m_displayNum(displayNum),
      m_displayCallbackRegistered(false)
{
    m_drawView = new DrawView(bgImage, this);
    setCentralWidget(m_drawView);

    // Window Flags for Overlay
    setWindowFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool | Qt::Popup);
    setAttribute(Qt::WA_ShowWithoutActivating);   
    setAttribute(Qt::WA_TranslucentBackground, false);
    
    // Geometry Setup
    setGeometry(geo);
    
    setContentsMargins(0, 0, 0, 0);
    m_drawView->setContentsMargins(0, 0, 0, 0);

    // Native macOS Magic: Disable Animations & Shadow
    winId(); // Force native window creation before getting the handle.
    QWindow *qwin = windowHandle();
    if (qwin) {
        QNativeInterface::QCocoaWindow *nativeWindow = qwin->nativeInterface<QNativeInterface::QCocoaWindow>();
        if (nativeWindow) {
            NSWindow *nswindow = nativeWindow->window();
            [nswindow setAnimationBehavior: NSWindowAnimationBehaviorNone];
            [nswindow setHasShadow:NO];
            [nswindow setLevel:NSFloatingWindowLevel]; // Stay above normal windows, but below system dialogs.
        } else {
            qWarning() << "Could not retrieve native Cocoa window interface for QWindow.";
        }
    } else {
        qWarning() << "Could not get QWindow handle for MainWindow.";
    }

    // Register Display Callback
    CGError err = CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallBack, this);
    if (err != kCGErrorSuccess) {
        qWarning() << "Failed to register display reconfiguration callback:" << err;
    } else {
        qDebug() << "Successfully registered display reconfiguration callback.";
        m_displayCallbackRegistered = true;
    }
}

MainWindow::~MainWindow()
{
    if (m_displayCallbackRegistered) {
        qDebug() << "Unregistering display reconfiguration callback.";
        CGDisplayRemoveReconfigurationCallback(DisplayReconfigurationCallBack, this);
    }
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    QApplication::exit(1);
    QMainWindow::closeEvent(event);
}