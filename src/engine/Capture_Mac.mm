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
#include <QNativeInterface> 

#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>

/**
 * Converts a CGImageRef to a QImage with proper memory management and stride handling.
 */
static QImage convertCGImageRefToQImage(CGImageRef imageRef)
{
    if (!imageRef) return QImage();

    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    
    CFDataRef dataRef = CGDataProviderCopyData(CGImageGetDataProvider(imageRef));
    if (!dataRef) {
        qWarning() << "Failed to copy CGImage data provider";
        return QImage();
    }

    const uchar *rawData = reinterpret_cast<const uchar*>(CFDataGetBytePtr(dataRef));
    size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);

    QImage tmp(rawData, static_cast<int>(width), static_cast<int>(height),
               static_cast<int>(bytesPerRow), QImage::Format_ARGB32_Premultiplied);

    QImage result = tmp.copy();
    CFRelease(dataRef);
    
    return result;
}

class CaptureEngineMac : public CaptureEngine
{
public:
    CaptureEngineMac(QObject *parent = nullptr) : CaptureEngine(parent) {}

    std::vector<CapturedFrame> captureAll() override {
        std::vector<CapturedFrame> frames;

        // Permission Check
        if (QOperatingSystemVersion::current() >= QOperatingSystemVersion::MacOSCatalina) {
            if (!CGPreflightScreenCaptureAccess()) {
                qWarning() << "No screen recording permission. Requesting...";
                CGRequestScreenCaptureAccess();
                qWarning() << "Please grant permissions and restart.";
                return frames; 
            }
        }

        int index = 0;
        const auto screens = QGuiApplication::screens();
        
        for (QScreen* screen : screens) {
            CGDirectDisplayID displayID = 0;

            // Use Qt 6's public native interface to get the display ID directly and safely.
            auto *native = screen->nativeInterface<QNativeInterface::QCocoaScreen>();
            if (native) {
                displayID = native->displayId();
            } else {
                qWarning() << "Could not retrieve native Cocoa screen interface for screen:" << screen->name();
                // Fallback (rare): try to guess main display if this is the first screen
                if (index == 0) {
                    displayID = CGMainDisplayID();
                } else {
                    index++;
                    continue;
                }
            }
            
            CGImageRef imgRef = CGDisplayCreateImage(displayID);
            if (!imgRef) {
                qWarning() << "Failed to capture display ID:" << displayID;
                index++;
                continue;
            }

            QImage qtImage = convertCGImageRefToQImage(imgRef);
            CGImageRelease(imgRef);

            if (qtImage.isNull()) {
                qWarning() << "Failed to convert CGImage to QImage.";
                index++;
                continue;
            }
            
            CapturedFrame frame;
            frame.image = qtImage;
            frame.geometry = screen->geometry();
            frame.devicePixelRatio = screen->devicePixelRatio();
            frame.index = index;
            frame.name = screen->name();
            
            frames.push_back(frame);
            index++;
        }
        
        CaptureEngine::sortLeftToRight(frames);
        return frames;
    }
};

extern "C" CaptureEngine* createUnixEngine(QObject* parent) {
    return new CaptureEngineMac(parent);
}