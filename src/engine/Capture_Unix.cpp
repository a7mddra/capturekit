/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

#include "Capture.h"
#include <QGuiApplication>
#include <QScreen>
#include <QPixmap>
#include <QDebug>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QEventLoop>
#include <QFile>
#include <QUuid>
#include <QUrl>
#include <cmath>

// =============================================================================
// HELPER: Portal Response Handler
// =============================================================================
class PortalHelper : public QObject {
    Q_OBJECT
public:
    QString savedUri;
    bool success = false;

public slots:
    void handleResponse(uint response, const QVariantMap &results) {
        if (response == 0) {
            savedUri = results.value("uri").toString();
            success = !savedUri.isEmpty();
        } else {
            qWarning() << "Portal request failed (Response Code:" << response << ")";
            success = false;
        }
        emit finished();
    }

signals:
    void finished();
};

// =============================================================================
// MAIN UNIX CAPTURE ENGINE
// =============================================================================
class CaptureEngineUnix : public CaptureEngine
{
public:
    CaptureEngineUnix(QObject *parent = nullptr) : CaptureEngine(parent) {}

    std::vector<CapturedFrame> captureAll() override {
        // ---------------------------------------------------------------------
        // CRITICAL FIX: Session Detection vs Platform Detection
        // ---------------------------------------------------------------------
        // Since we are forcing QT_QPA_PLATFORM=xcb in main.cpp, 
        // QGuiApplication::platformName() will return "xcb".
        // This causes the logic to mistakenly choose captureStandard() (grabWindow),
        // which returns black screens on Wayland.
        //
        // We must check the ENVIRONMENT to see if we are actually in a Wayland session.
        // ---------------------------------------------------------------------
        
        QString sessionType = qgetenv("XDG_SESSION_TYPE").toLower();
        
        // Use Portal if we are on Wayland, regardless of how Qt is rendering.
        if (sessionType == "wayland") {
            qDebug() << "Wayland session detected (forcing Portal capture despite XCB backend).";
            return captureWayland();
        } else {
            qDebug() << "X11 session detected (using standard capture).";
            return captureStandard();
        }
    }

private:
    // --- X11 / macOS (Standard Memory Grab) ---
    std::vector<CapturedFrame> captureStandard() {
        std::vector<CapturedFrame> frames;
        const auto screens = QGuiApplication::screens();
        int index = 0;

        for (QScreen* screen : screens) {
            if (!screen) continue;
            QPixmap pixmap = screen->grabWindow(0);
            if (pixmap.isNull()) continue;

            CapturedFrame frame;
            frame.image = pixmap.toImage(); 
            frame.geometry = screen->geometry();
            frame.devicePixelRatio = screen->devicePixelRatio();
            frame.name = screen->name();
            frame.index = index++;
            frames.push_back(frame);
        }
        CaptureEngine::sortLeftToRight(frames);
        return frames;
    }

    // --- Wayland (The Giant Image Slicer) ---
    std::vector<CapturedFrame> captureWayland() {
        std::vector<CapturedFrame> frames;
        
        // 1. Setup DBus Interface
        QDBusInterface portal(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot"
        );

        if (!portal.isValid()) {
            qCritical() << "Portal interface not found.";
            return frames;
        }

        // 2. Request Silent Capture (interactive: false)
        QString token = QUuid::createUuid().toString().remove('{').remove('}').remove('-');
        QVariantMap options;
        options["handle_token"] = token;
        options["interactive"] = false; 

        QDBusReply<QDBusObjectPath> reply = portal.call("Screenshot", "", options);
        if (!reply.isValid()) {
            qCritical() << "Portal call failed:" << reply.error().message();
            return frames;
        }

        // 3. Wait for the file
        PortalHelper helper;
        QEventLoop loop;
        QDBusConnection::sessionBus().connect(
            "org.freedesktop.portal.Desktop", reply.value().path(),
            "org.freedesktop.portal.Request", "Response",
            &helper, SLOT(handleResponse(uint, QVariantMap))
        );
        QObject::connect(&helper, &PortalHelper::finished, &loop, &QEventLoop::quit);
        loop.exec();

        if (!helper.success) return frames;

        // 4. Load the Giant Image
        QString localPath = QUrl(helper.savedUri).toLocalFile();
        QImage fullDesktop(localPath);
        QFile::remove(localPath); // Delete immediately

        if (fullDesktop.isNull()) {
            qCritical() << "Downloaded image is null.";
            return frames;
        }

        // =========================================================
        // SLICER LOGIC
        // =========================================================
        
        // A. Calculate Logical Bounds
        QRect logicalBounds;
        for (QScreen* screen : QGuiApplication::screens()) {
            logicalBounds = logicalBounds.united(screen->geometry());
        }

        // B. Calculate Global Scale
        // Note: When running in XCB on Wayland, logicalBounds might report the XWayland 
        // bounds, while fullDesktop is the raw Wayland compositor screenshot.
        // This ratio calculation remains valid and necessary.
        double scaleFactor = 1.0;
        if (logicalBounds.width() > 0) {
            scaleFactor = (double)fullDesktop.width() / (double)logicalBounds.width();
        }
        
        qDebug() << "Capture Info: Image" << fullDesktop.size() 
                 << "Logical" << logicalBounds 
                 << "Scale" << scaleFactor;

        int index = 0;
        for (QScreen* screen : QGuiApplication::screens()) {
            QRect geo = screen->geometry();

            int cropX = std::round((geo.x() - logicalBounds.x()) * scaleFactor);
            int cropY = std::round((geo.y() - logicalBounds.y()) * scaleFactor);
            int cropW = std::round(geo.width() * scaleFactor);
            int cropH = std::round(geo.height() * scaleFactor);

            if (cropX < 0) cropX = 0;
            if (cropY < 0) cropY = 0;
            if (cropX + cropW > fullDesktop.width()) cropW = fullDesktop.width() - cropX;
            if (cropY + cropH > fullDesktop.height()) cropH = fullDesktop.height() - cropY;

            QImage screenImg = fullDesktop.copy(cropX, cropY, cropW, cropH);
            screenImg.setDevicePixelRatio(scaleFactor);

            CapturedFrame frame;
            frame.image = screenImg;
            frame.geometry = geo;
            frame.devicePixelRatio = scaleFactor;
            frame.name = screen->name();
            frame.index = index++;

            frames.push_back(frame);
        }

        CaptureEngine::sortLeftToRight(frames);
        return frames;
    }
};

#include "Capture_Unix.moc"

extern "C" CaptureEngine* createUnixEngine(QObject* parent) {
    return new CaptureEngineUnix(parent);
}
