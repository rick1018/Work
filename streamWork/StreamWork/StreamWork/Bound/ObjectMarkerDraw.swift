//
//  ObjectMarkerDraw.swift
//  StreamWork
//
//  Created by Rick_hsu on 2021/9/16.
//

import UIKit
import CoreMedia
import Vision

class ObjectMarkerDraw {
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let boundingBoxView = BoundingBoxView()

    func drawMarkers(for observations: [VNRecognizedObjectObservation], onto pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        autoreleasepool {
            // Lock pixelBuffer to start adding mask on it
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            }

            //Deep copy buffer pixel to avoid memory leak
            var processedPixelBuffer: CVPixelBuffer? = nil
            let options = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ] as CFDictionary

            let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                             CVPixelBufferGetWidth(pixelBuffer),
                                             CVPixelBufferGetHeight(pixelBuffer),
                                             kCVPixelFormatType_32BGRA, options,
                                             &processedPixelBuffer)
            guard status == kCVReturnSuccess else { return nil }

            // Lock destination buffer until we finish the drawing
            CVPixelBufferLockBaseAddress(processedPixelBuffer!,
                                         CVPixelBufferLockFlags(rawValue: 0))

            defer {
                CVPixelBufferUnlockBaseAddress(processedPixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
            }

            guard let processedPixelBufferUnwrapped = processedPixelBuffer,
                let processedPixelBufferBaseAddress = CVPixelBufferGetBaseAddress(processedPixelBuffer!)
            else {
                return nil
            }

            memcpy(processedPixelBufferBaseAddress,
                   CVPixelBufferGetBaseAddress(pixelBuffer),
                   CVPixelBufferGetHeight(pixelBuffer) * CVPixelBufferGetBytesPerRow(pixelBuffer))

            let width = CVPixelBufferGetWidth(processedPixelBufferUnwrapped)
            let height = CVPixelBufferGetHeight(processedPixelBufferUnwrapped)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(processedPixelBufferUnwrapped)
            guard let context = CGContext(data: processedPixelBufferBaseAddress,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue)
            else { return nil }

            // Show the bounding box for each object
            let scale = CGAffineTransform.identity.scaledBy(x: CGFloat(width), y: CGFloat(height))
            for feature in observations {
                let label = String(format: "Person %.1f", feature.confidence * 100)
                let color = UIColor.red
                let rect = feature.boundingBox.applying(scale)
                let boundingBoxLayers = boundingBoxView.getLayers(frame: rect, label: label, color: color)
                boundingBoxLayers.shapeLayer.render(in: context)
                context.translateBy(x: rect.origin.x, y: rect.origin.y)
                boundingBoxLayers.textLayer.render(in: context)
            }

            return processedPixelBufferUnwrapped
        }
    }

}
