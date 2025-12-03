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
        QString platform = QGuiApplication::platformName();
        // Force Wayland path if detected, otherwise fallback to X11/Cocoa
        if (platform.startsWith("wayland")) {
            return captureWayland();
        } else {
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
        // Note: Some compositors might ignore this and show a prompt anyway, 
        // but this flag tells them "we prefer no UI".
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
        // THE SLICER LOGIC (Flameshot Adaptation)
        // =========================================================

        // A. Calculate the bounds of the "Logical" desktop (Qt coordinates)
        QRect logicalBounds;
        for (QScreen* screen : QGuiApplication::screens()) {
            logicalBounds = logicalBounds.united(screen->geometry());
        }

        // B. Determine the Global Scale Factor
        // The Portal image is usually in raw physical pixels.
        // Qt geometries are in logical pixels (e.g., scaled by 200%).
        // We calculate the ratio between the big image width and the logical width.
        double scaleFactor = 1.0;
        if (logicalBounds.width() > 0) {
            scaleFactor = (double)fullDesktop.width() / (double)logicalBounds.width();
        }
        
        qDebug() << "Giant Image Size:" << fullDesktop.size();
        qDebug() << "Logical Bounds:" << logicalBounds;
        qDebug() << "Calculated Global Scale:" << scaleFactor;

        int index = 0;
        for (QScreen* screen : QGuiApplication::screens()) {
            QRect geo = screen->geometry();

            // C. Map Logical Coordinates to Physical Image Coordinates
            // We must subtract the logicalBounds.x() because the virtual desktop 
            // might start at negative coordinates (e.g. secondary monitor on the left).
            int cropX = std::round((geo.x() - logicalBounds.x()) * scaleFactor);
            int cropY = std::round((geo.y() - logicalBounds.y()) * scaleFactor);
            int cropW = std::round(geo.width() * scaleFactor);
            int cropH = std::round(geo.height() * scaleFactor);

            // Safety clamp to prevent crashing on rounding errors
            if (cropX < 0) cropX = 0;
            if (cropY < 0) cropY = 0;
            if (cropX + cropW > fullDesktop.width()) cropW = fullDesktop.width() - cropX;
            if (cropY + cropH > fullDesktop.height()) cropH = fullDesktop.height() - cropY;

            // D. Crop
            QImage screenImg = fullDesktop.copy(cropX, cropY, cropW, cropH);

            // E. Set DPR
            // This ensures the image doesn't look "zoomed in" when displayed 
            // on a high-DPI logical window.
            screenImg.setDevicePixelRatio(scaleFactor);

            CapturedFrame frame;
            frame.image = screenImg;
            frame.geometry = geo;
            frame.devicePixelRatio = scaleFactor; // Use the calculated scale, not the OS reported one
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
