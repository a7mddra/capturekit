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
#include <QMessageBox>

#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>

/**
 * Converts a CGImageRef to a QImage with proper memory management, stride handling, and color space.
 */
static QImage convertCGImageRefToQImage(CGImageRef imageRef, CGDirectDisplayID displayID)
{
    if (!imageRef) return QImage();

    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    
    if (width == 0 || height == 0) {
        return QImage();
    }

    size_t bytesPerPixel = 4;
    size_t bytesPerRow = bytesPerPixel * width;
    std::vector<unsigned char> buffer(bytesPerRow * height);

    // Use the display's actual color space for accuracy, with a fallback to generic sRGB.
    CGColorSpaceRef colorSpace = CGDisplayCopyColorSpace(displayID);
    if (!colorSpace) {
        qWarning() << "Could not get display color space, falling back to sRGB.";
        colorSpace = CGColorSpaceCreateDeviceRGB();
        if (!colorSpace) {
            qWarning() << "Failed to create any color space!";
            return QImage();
        }
    }

    // Create a bitmap context with a known ARGB format (little-endian for modern Macs).
    CGContextRef ctx = CGBitmapContextCreate(buffer.data(), width, height, 8, bytesPerRow, colorSpace,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    
    if (!ctx) {
        qWarning() << "Failed to create CGBitmapContext";
        CGColorSpaceRelease(colorSpace);
        return QImage();
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), imageRef);

    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    // Create a QImage from the buffer, then do a deep copy.
    QImage img(buffer.data(), static_cast<int>(width), static_cast<int>(height),
               static_cast<int>(bytesPerRow), QImage::Format_ARGB32_Premultiplied);
    
    return img.copy();
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
                // We don't have permission, so we request it.
                CGRequestScreenCaptureAccess();

                // Inform the user about the required action.
                QMessageBox msgBox;
                msgBox.setIcon(QMessageBox::Information);
                msgBox.setWindowTitle(tr("Screen Recording Permission"));
                msgBox.setText(tr("CaptureKit requires screen recording permission to take screenshots."));
                msgBox.setInformativeText(tr("Please go to System Settings > Privacy & Security > Screen Recording, "
                                              "and enable CaptureKit. You will need to restart the application afterwards."));
                msgBox.setStandardButtons(QMessageBox::Ok);
                msgBox.exec();

                // Return empty frames to allow the application to exit gracefully.
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

            QImage qtImage = convertCGImageRefToQImage(imgRef, displayID);
            CGImageRelease(imgRef);

            if (qtImage.isNull()) {
                qWarning() << "Failed to convert CGImage to QImage.";
                index++;
                continue;
            }

            qtImage.setDevicePixelRatio(screen->devicePixelRatio());
            
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