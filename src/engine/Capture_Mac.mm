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
#include <QPushButton>

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

#ifndef NDEBUG
    if (width > 0 && height > 0) {
        // Quick pixel sanity check after creating the image in debug builds.
        QRgb p = img.pixel(0, 0);
        qDebug() << "Captured pixel (ARGB):" << qAlpha(p) << qRed(p) << qGreen(p) << qBlue(p);
    }
#endif
    
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

                // Inform the user about the required action with an improved dialog.
                QMessageBox msgBox;
                msgBox.setIcon(QMessageBox::Information);
                msgBox.setWindowTitle(tr("Screen Recording Permission"));
                msgBox.setText(tr("CaptureKit requires screen recording permission to take screenshots."));
                msgBox.setInformativeText(tr("Please grant permission in System Settings. The application will close after. A restart may be required."));
                
                QPushButton *openSettingsButton = msgBox.addButton(tr("Open System Settings"), QMessageBox::ActionRole);
                msgBox.setStandardButtons(QMessageBox::Cancel);
                msgBox.setDefaultButton(openSettingsButton);

                msgBox.exec();

                if (msgBox.clickedButton() == openSettingsButton) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording"]];
                }

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
                qWarning() << "Attempting to match screen by geometry as a fallback.";

                const int maxDisplays = 16; // A reasonable limit
                CGDirectDisplayID displays[maxDisplays];
                uint32_t displayCount = 0;

                if (CGGetActiveDisplayList(maxDisplays, displays, &displayCount) != kCGErrorSuccess) {
                    qWarning() << "Fallback failed: Could not get active display list.";
                    index++;
                    continue;
                }

                bool foundMatch = false;
                for (uint32_t i = 0; i < displayCount; ++i) {
                    CGRect cgRect = CGDisplayBounds(displays[i]);
                    QRect qtRect(static_cast<int>(cgRect.origin.x), static_cast<int>(cgRect.origin.y),
                                 static_cast<int>(cgRect.size.width), static_cast<int>(cgRect.size.height));

                    if (qtRect == screen->geometry()) {
                        displayID = displays[i];
                        foundMatch = true;
                        qInfo() << "Fallback successful: Matched screen by geometry to display ID" << displayID;
                        break;
                    }
                }

                if (!foundMatch) {
                    qWarning() << "Fallback failed: Could not match screen geometry. Skipping screen.";
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