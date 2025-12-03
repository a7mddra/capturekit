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

    // [FIX] Native macOS Magic: Use standard casting instead of QNativeInterface
    // Force native window creation.
    WId nativeId = this->winId(); 
    
    NSView *nativeView = reinterpret_cast<NSView *>(nativeId);
    if (nativeView) {
        NSWindow *nswindow = [nativeView window];
        if (nswindow) {
            [nswindow setAnimationBehavior: NSWindowAnimationBehaviorNone];
            [nswindow setHasShadow:NO];
            [nswindow setLevel:NSFloatingWindowLevel]; 
        } else {
             qWarning() << "Could not retrieve NSWindow from NSView.";
        }
    } else {
        qWarning() << "Could not retrieve native view handle.";
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