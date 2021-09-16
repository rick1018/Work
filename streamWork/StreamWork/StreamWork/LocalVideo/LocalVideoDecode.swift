//
//  LocalVideoDecode.swift
//  StreamWork
//
//  Created by Rick_hsu on 2021/9/15.
//

import UIKit
import CoreMedia
import CoreML
import Vision
import AVKit
import MobileCoreServices

class LocalVideoDecode: UIViewController, UIImagePickerControllerDelegate ,UINavigationControllerDelegate {
    
    var imagePickerController = UIImagePickerController()
    var videoURL: URL?
    var displayview:glDisplayview!
    var currentBuffer: CVPixelBuffer?
    var fileCapture:VideoFileCapture!
    let coreMLModel = MobileNetV2_SSDLite()
    var currentBufferTimestamp: CMTime?//currentSampleBuffer: CMSampleBuffer?  // Remove if object marking is implemented
    var lastTimePersonWasDetected: CMTime?
    
    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()
    
    var recording = false
    lazy var recorder: RecordFile = {
        let recorder = RecordFile()
        recorder.delegate = self
        return recorder
    }()
    
    let objectMarkerDrawer = ObjectMarkerDraw()
    
    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel, completionHandler: {
            [weak self] request, error in
            self?.processObservations(for: request, error: error)
        })
        
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()
    
    let maxBoundingBoxViews = 10
    var boundingBoxViews = [BoundingBoxView]()
    var colors: [String: UIColor] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        var leftButton: UIBarButtonItem = UIBarButtonItem(title: "選取影片", style: UIBarButtonItem.Style.bordered, target: self, action: #selector(openImgPicker))
        
        self.navigationItem.rightBarButtonItem = leftButton
        self.navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    func setUpBoundingBoxViews() {
        for _ in 0..<maxBoundingBoxViews {
            boundingBoxViews.append(BoundingBoxView())
        }
        
        // The label names are stored inside the MLModel's metadata.
        guard let userDefined = coreMLModel.model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String],
              let allLabels = userDefined["classes"] else {
            fatalError("Missing metadata")
        }
        
        let labels = allLabels.components(separatedBy: ",")
        
        // Assign random colors to the classes.
        for label in labels {
            colors[label] = UIColor(red: CGFloat.random(in: 0...1),
                                    green: CGFloat.random(in: 0...1),
                                    blue: CGFloat.random(in: 0...1),
                                    alpha: 1)
        }
    }
    
    func predict(sampleBuffer: CMSampleBuffer) {
        if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            currentBuffer = pixelBuffer
            displayview.displayPixelBuffer(currentBuffer!)
            currentBufferTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            // Get additional info from the camera.
            var options: [VNImageOption : Any] = [:]
            if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
                options[.cameraIntrinsics] = cameraIntrinsicMatrix
            }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: options)
            do {
                try handler.perform([self.visionRequest])
            } catch {
                print("Failed to perform Vision request: \(error)")
            }
            
            currentBuffer = nil
            currentBufferTimestamp = nil
        }
    }
    
    func processObservations(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            if let results = request.results as? [VNRecognizedObjectObservation] {
                self.show(predictions: results)
            } else {
                self.show(predictions: [])
            }
        }
        
        if let results = request.results as? [VNRecognizedObjectObservation],
           let timestamp = currentBufferTimestamp {
            let personResults = results.filter { (observation) -> Bool in
                observation.labels.first?.identifier == "person"
            }
            
            if !recording && !personResults.isEmpty {
                recording = true
            }
            
            if !personResults.isEmpty, let pixelBuffer = currentBuffer {
                lastTimePersonWasDetected = timestamp
                // Draw marker
                guard let processedPixelBuffer = objectMarkerDrawer.drawMarkers(for: personResults, onto: pixelBuffer)
                else { return }
                
                if !recorder.appendSampleBuffer(buffer: processedPixelBuffer, timestamp: timestamp) {
                    recorder.saveFile()
                    // Video duration has a 10 seconds limit
                    // Trigger another recording for this new detection
                    recorder = RecordFile()
                    recorder.delegate = self
                    recorder.appendSampleBuffer(buffer: processedPixelBuffer, timestamp: timestamp)
                }
            } else if recording, let buffer = currentBuffer, let lastTimePersonWasDetected = lastTimePersonWasDetected {
                if CMTimeSubtract(timestamp, lastTimePersonWasDetected).seconds > 5 {
                    // There is no person detected within 5 seconds, save file and prepare next recording
                    recorder.saveFile()
                    recorder = RecordFile()
                    recorder.delegate = self
                    recording = false
                    self.lastTimePersonWasDetected = nil
                } else if !recorder.appendSampleBuffer(buffer: buffer, timestamp: timestamp) {
                    // Discard this buffer and stop recording due to 10 sec limit
                    recorder.saveFile()
                    // Trigger another recording for this new detection
                    recorder = RecordFile()
                    recorder.delegate = self
                    recording = false
                    self.lastTimePersonWasDetected = nil
                }
            }
        }
    }
    
    func show(predictions: [VNRecognizedObjectObservation]) {
        for i in 0..<boundingBoxViews.count {
            if i < predictions.count {
                let prediction = predictions[i]
                
                let width = view.bounds.width
                let height = width * 16 / 9
                let offsetY = (view.bounds.height - height) / 2
                let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
                let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
                let rect = prediction.boundingBox.applying(scale).applying(transform)
                
                // The labels array is a list of VNClassificationObservation objects,
                // with the highest scoring class first in the list.
                let bestClass = prediction.labels[0].identifier
                let confidence = prediction.labels[0].confidence
                
                // Show the bounding box.
                let label = String(format: "%@ result=============%.1f", bestClass, confidence * 100)
                print(bestClass);
                let color = colors[bestClass] ?? UIColor.red
                boundingBoxViews[i].show(frame: rect, label: label, color: color)
            } else {
                boundingBoxViews[i].hide()
            }
        }
    }
    
    @objc private func openImgPicker() {
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.delegate = self
        imagePickerController.mediaTypes = ["public.movie"]
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        videoURL = (info[UIImagePickerController.InfoKey(rawValue: UIImagePickerController.InfoKey.mediaURL.rawValue)] as! URL)
        
        setUpBoundingBoxViews()
        displayview = glDisplayview(frame:CGRect(x: 0, y: 64, width: self.view.frame.size.width, height: self.view.frame.size.height - 64 ))
        self.view.addSubview(displayview)
        
        for box in self.boundingBoxViews {
            box.addToLayer(self.displayview.layer)
        }
        
        fileCapture = VideoFileCapture(fileURL: videoURL!)
        fileCapture.delegate = self
        fileCapture.processFrames()
        self.dismiss(animated: true, completion: nil)
    }
}

extension LocalVideoDecode: RecordFileDelegate {
    
    func eventVideoRecorderDidSavedVideo(_ recorder: RecordFile) {
        if fileCapture.finished {
            displayExportFinishedUIIfNeeded()
        }
    }
    
    func eventVideoRecorderNeedsLibraryPermission(_ recorder: RecordFile) {
        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Please turn on permission for photo library", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }
    
    func eventVideoRecorderFailedToSavedVideo(_ recorder: RecordFile) {
        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Fail to save video to library", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }
    
    
}

extension LocalVideoDecode: VideoFileCaptureDelegate {
    
    func videoFileCapture(_ capture: VideoFileCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        predict(sampleBuffer: sampleBuffer)
    }
    
    func videoFileCaptureFinished(_ capture: VideoFileCapture) {
        if recorder.hasData {
            recorder.saveFile()
            recording = false
            lastTimePersonWasDetected = nil
        } else {
            displayExportFinishedUIIfNeeded()
        }
    }
    
    func videoFileCaptureFailed(_ capture: VideoFileCapture) {
        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Failed to read source video", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }
    
    func displayExportFinishedUIIfNeeded() {
        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Event videos have been saved into Photo Library", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }
}
