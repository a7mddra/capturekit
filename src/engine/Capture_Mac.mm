/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

#include "Capture.h"
#include <QGuiApplication>
#include <QScreen>
#include <QDebug>
#include <QOperatingSystemVersion>

#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>

/**
 * Converts a CGImageRef to a QImage.
 *
 * This function creates a CGBitmapContext, draws the CGImageRef into it,
 * and then copies the raw pixel data into a QImage. This is the robust
 * way to perform the conversion in Qt 6 without relying on deprecated
 * or external modules.
 *
 * @param imageRef The native macOS image reference.
 * @return A QImage containing the pixel data.
 */
static QImage convertCGImageRefToQImage(CGImageRef imageRef)
{
    if (!imageRef) {
        return QImage();
    }

    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    size_t bitsPerComponent = CGImageGetBitsPerComponent(imageRef);
    size_t bitsPerPixel = CGImageGetBitsPerPixel(imageRef);
    size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(imageRef);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);

    if (bitsPerComponent != 8 || bitsPerPixel != 32) {
        qWarning() << "Unsupported image format, falling back to slower conversion.";
        // Fallback for non-32bit RGBA images: draw into a new context.
        CGColorSpaceRef colorSpaceRGB = CGColorSpaceCreateDeviceRGB();
        // Force an ARGB context.
        bitmapInfo = kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst;
        bytesPerRow = 4 * width;
        CGContextRef context = CGBitmapContextCreate(nullptr, width, height, 8, bytesPerRow, colorSpaceRGB, bitmapInfo);
        CGColorSpaceRelease(colorSpaceRGB);

        if (!context) {
            qWarning() << "Failed to create bitmap context for image conversion.";
            return QImage();
        }

        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
        void* data = CGBitmapContextGetData(context);
        QImage image(static_cast<uchar*>(data), width, height, QImage::Format_ARGB32_Premultiplied);
        
        // We need to copy the data because the context will be released.
        QImage copiedImage = image.copy();
        CGContextRelease(context);
        return copiedImage;
    }

    const uchar *rawData = (const uchar *)CFDataGetBytePtr(CGDataProviderCopyData(CGImageGetDataProvider(imageRef)));
    QImage image(rawData, width, height, QImage::Format_ARGB32_Premultiplied);

    // The data is owned by the CGImage, so we must make a deep copy.
    return image.copy();
}


class CaptureEngineMac : public CaptureEngine
{
public:
    CaptureEngineMac(QObject *parent = nullptr) : CaptureEngine(parent) {}

    std.vector<CapturedFrame> captureAll() override {
        std::vector<CapturedFrame> frames;

        // On modern macOS, we must have screen capture permissions.
        // This check requires linking against AppKit.
        if (QOperatingSystemVersion::current() >= QOperatingSystemVersion::MacOSCatalina) {
            if (!CGPreflightScreenCaptureAccess()) {
                qWarning() << "No screen recording permission. Requesting...";
                // This function returns immediately and doesn't block.
                // The user must grant permission in System Preferences.
                // The app needs to be restarted after permission is granted.
                CGRequestScreenCaptureAccess();
                qWarning() << "Please grant screen recording permissions in System Settings and restart the application.";
                return frames; // Return empty, as capture will fail.
            }
        }

        int index = 0;
        for (QScreen* screen : QGuiApplication::screens()) {
            // Use the screen's native handle to get its display ID.
            // This requires some bridging between Qt and AppKit/CoreGraphics.
            // A common way is to get the NSView for a QWindow on this screen.
            // However, a more direct way for screens is via this private Qt API.
            // Note: This relies on Qt's internal macOS implementation details.
            unsigned int displayID = screen->handle()->nativeResourceForScreen("displayId").toUInt();
            
            CGImageRef imgRef = CGDisplayCreateImage(displayID);
            if (!imgRef) {
                qWarning() << "Failed to capture screen with display ID:" << displayID;
                continue;
            }

            QImage qtImage = convertCGImageRefToQImage(imgRef);
            CGImageRelease(imgRef);

            if (qtImage.isNull()) {
                qWarning() << "Failed to convert native CGImage to QImage for display ID:" << displayID;
                continue;
            }
            
            CapturedFrame frame;
            frame.image = qtImage;
            frame.geometry = screen->geometry();
            frame.devicePixelRatio = screen->devicePixelRatio();
            frame.index = index++;
            frame.name = screen->name();
            
            frames.push_back(frame);
        }
        
        CaptureEngine::sortLeftToRight(frames);
        return frames;
    }
};

// Factory function that gets called in main.cpp
extern "C" CaptureEngine* createUnixEngine(QObject* parent) {
    return new CaptureEngineMac(parent);
}
