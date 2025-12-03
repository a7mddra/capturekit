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
#include <QStandardPaths>

// =============================================================================
// INTERNAL HELPER: Portal Response Receiver
// Handles the asynchronous signal from the Freedesktop Portal
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
            qWarning() << "Portal request denied or failed. Code:" << response;
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
        qDebug() << "CaptureEngineUnix detected platform:" << platform;

        if (platform.startsWith("wayland")) {
            return captureWayland();
        } else {
            return captureStandard(); // X11 or macOS
        }
    }

private:
    // --- X11 / macOS (Fast, In-Memory) ---
    std::vector<CapturedFrame> captureStandard() {
        std::vector<CapturedFrame> frames;
        const auto screens = QGuiApplication::screens();
        int index = 0;

        for (QScreen* screen : screens) {
            if (!screen) continue;

            // grabWindow(0) is optimized on X11 and Cocoa
            QPixmap pixmap = screen->grabWindow(0);
            
            if (pixmap.isNull()) {
                qWarning() << "Failed to grab screen:" << screen->name();
                continue;
            }

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

    // --- Wayland (Portal / DBus) ---
    std::vector<CapturedFrame> captureWayland() {
        std::vector<CapturedFrame> frames;
        
        // 1. Prepare DBus Call
        QDBusInterface portal(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot"
        );

        if (!portal.isValid()) {
            qCritical() << "Wayland Portal interface not found!";
            return frames;
        }

        // 2. Generate unique token & prepare options
        QString token = QUuid::createUuid().toString().remove('{').remove('}').remove('-');
        QVariantMap options;
        options["handle_token"] = token;
        options["interactive"] = false; // Silent capture

        // 3. Call 'Screenshot' method
        QDBusReply<QDBusObjectPath> reply = portal.call("Screenshot", "", options);
        
        if (!reply.isValid()) {
            qCritical() << "Portal Screenshot call failed:" << reply.error().message();
            return frames;
        }

        // 4. Setup Signal Listener (The Request Object)
        QString requestPath = reply.value().path();
        PortalHelper helper;
        QEventLoop loop;

        QDBusConnection::sessionBus().connect(
            "org.freedesktop.portal.Desktop",
            requestPath,
            "org.freedesktop.portal.Request",
            "Response",
            &helper,
            SLOT(handleResponse(uint, QVariantMap))
        );

        QObject::connect(&helper, &PortalHelper::finished, &loop, &QEventLoop::quit);

        // 5. Wait for User/System (Blocking)
        qDebug() << "Waiting for Wayland Portal response...";
        loop.exec();

        if (!helper.success) {
            return frames;
        }

        // 6. Process Result
        QString localPath = QUrl(helper.savedUri).toLocalFile();
        QImage fullDesktop(localPath);

        if (fullDesktop.isNull()) {
            qCritical() << "Failed to load image from Portal:" << localPath;
            return frames;
        }

        // 7. Cleanup File (Zero-Storage Policy)
        QFile::remove(localPath);

        // 8. SLICE THE GIANT IMAGE
        // Portals usually return one giant combined image. 
        // We must crop it based on Qt's understanding of screen geometry.
        
        QRect logicalBounds;
        for (QScreen* screen : QGuiApplication::screens()) {
            logicalBounds = logicalBounds.united(screen->geometry());
        }

        // Check if we need to scale (HiDPI handling)
        qreal scaleFactor = 1.0;
        if (fullDesktop.width() != logicalBounds.width()) {
            scaleFactor = (qreal)fullDesktop.width() / (qreal)logicalBounds.width();
        }

        int index = 0;
        for (QScreen* screen : QGuiApplication::screens()) {
            QRect geo = screen->geometry();
            
            // Map logical screen geometry to the actual screenshot pixels
            QRect cropRect(
                (geo.x() - logicalBounds.x()) * scaleFactor,
                (geo.y() - logicalBounds.y()) * scaleFactor,
                geo.width() * scaleFactor,
                geo.height() * scaleFactor
            );

            QImage screenImg = fullDesktop.copy(cropRect);

            CapturedFrame frame;
            frame.image = screenImg;
            frame.geometry = geo;
            frame.devicePixelRatio = screen->devicePixelRatio();
            frame.name = screen->name();
            frame.index = index++;
            
            frames.push_back(frame);
        }

        CaptureEngine::sortLeftToRight(frames);
        return frames;
    }
};

#include "Capture_Unix.moc"

// Factory definition
extern "C" CaptureEngine* createUnixEngine(QObject* parent) {
    return new CaptureEngineUnix(parent);
}
