//
//  RecordFile.swift
//  StreamWork
//
//  Created by Rick_hsu on 2021/9/16.
//

import Foundation
import AVFoundation
import Photos


public protocol RecordFileDelegate: class {
    func eventVideoRecorderDidSavedVideo(_ recorder:  RecordFile)
    func eventVideoRecorderNeedsLibraryPermission(_ recorder:  RecordFile)
    func eventVideoRecorderFailedToSavedVideo(_ recorder:  RecordFile)
}

public class RecordFile {

    private let writerInput: AVAssetWriterInput
    private let writer: AVAssetWriter
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let eventVideoTimeLimit: Float64 = 10

    private var startTime: CMTime?  // Not sure why duration of CMSampleBuffer is invalid, so use time calculation to get a rough value
    private(set) var hasData = false
    private var writingFinished = false

    weak var delegate: RecordFileDelegate?

    init() {
        let settings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(1080)),
            AVVideoHeightKey: NSNumber(value: Float(1920))
        ]
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.mediaTimeScale = CMTimeScale(600)

        let filePath = NSTemporaryDirectory() + "tempVideo_\(Date().timeIntervalSince1970).mp4"
        if FileManager.default.fileExists(atPath: filePath) {
            try! FileManager.default.removeItem(atPath: filePath)
        }
        writer = try! AVAssetWriter(url: URL(fileURLWithPath: filePath), fileType: .mp4)
        writer.add(writerInput)

        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                       sourcePixelBufferAttributes: nil)
    }

    @discardableResult
    func appendSampleBuffer(buffer: CVPixelBuffer, timestamp: CMTime) -> Bool {
        guard !writingFinished else { return false }

        if startTime == nil {
            startTime = timestamp
            hasData =  true
            writer.startWriting()
            writer.startSession(atSourceTime: CMTime.zero)
        }

        let presentationTime = CMTime(seconds: timestamp.seconds - startTime!.seconds,
                                      preferredTimescale: writerInput.mediaTimeScale)
        while !writerInput.isReadyForMoreMediaData {
            let date = Date().addingTimeInterval(0.01)
            RunLoop.current.run(until: date)
        }
        return adaptor.append(buffer, withPresentationTime: presentationTime)
    }

    func saveFile() {
        guard hasData else {
            DispatchQueue.main.async {
                self.delegate?.eventVideoRecorderFailedToSavedVideo(self)
            }
            return
        }

        startTime = nil
        writingFinished = true

        writer.finishWriting {
            PHPhotoLibrary.requestAuthorization { (status) in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.writer.outputURL)
                    }) { (success, error) in
                        if let error = error {
                            print("\(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.delegate?.eventVideoRecorderFailedToSavedVideo(self)
                            }
                        } else {
                            print("Video has been exported to photo library.")
                            DispatchQueue.main.async {
                                self.delegate?.eventVideoRecorderDidSavedVideo(self)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.eventVideoRecorderNeedsLibraryPermission(self)
                    }
                }
            }
        }
    }
}
