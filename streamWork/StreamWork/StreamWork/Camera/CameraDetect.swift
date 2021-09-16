//
//  CameraDetect.swift
//  StreamWork
//
//  Created by Rick_hsu on 2021/9/15.
//

import UIKit
import AVFoundation
import CoreVideo
import Vision


class CameraDetect: UIViewController {
    var preview:glDisplayview!
    var _videoCapture: videoCapture!
    var currentBuffer: CVPixelBuffer?
    var currentBufferTimestamp: CMTime?//currentSampleBuffer: CMSampleBuffer?  // Remove if object marking is implemented
    var lastTimePersonWasDetected: CMTime?
    let coreMLModel = MobileNetV2_SSDLite()
    
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

      // NOTE: If you use another crop/scale option, you must also change
      // how the BoundingBoxView objects get scaled when they are drawn.
      // Currently they assume the full input image is used.
      request.imageCropAndScaleOption = .scaleFill
      return request
    }()

    let maxBoundingBoxViews = 10
    var boundingBoxViews = [BoundingBoxView]()
    var colors: [String: UIColor] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.preview = glDisplayview(frame:CGRect(x: 0, y: 64, width: self.view.frame.size.width, height: self.view.frame.size.height - 64 ))
        self.preview.backgroundColor = UIColor.black
        self.view.addSubview(preview)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setUpBoundingBoxViews()
        setUpCamera()
        self.navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        _videoCapture.stop()
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
    
    func setUpCamera() {
        _videoCapture = StreamWork.videoCapture()
      _videoCapture.delegate = self

        _videoCapture.setUp(sessionPreset: .hd1280x720) { success in
        if success {


          // Add the bounding box layers to the UI, on top of the video preview.
          for box in self.boundingBoxViews {
            box.addToLayer(self.preview.layer)
          }

          // Once everything is set up, we can start capturing live video.
          self._videoCapture.start()
        }
      }
    }
    
    override func viewWillLayoutSubviews() {
      super.viewWillLayoutSubviews()
     
    }


    func predict(sampleBuffer: CMSampleBuffer) {
      if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        currentBuffer = pixelBuffer
        currentBufferTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        preview.displayPixelBuffer(currentBuffer!)
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

          /*
           The predicted bounding box is in normalized image coordinates, with
           the origin in the lower-left corner.

           Scale the bounding box to the coordinate system of the video preview,
           which is as wide as the screen and has a 16:9 aspect ratio. The video
           preview also may be letterboxed at the top and bottom.

           Based on code from https://github.com/Willjay90/AppleFaceDetection

           NOTE: If you use a different .imageCropAndScaleOption, or a different
           video resolution, then you also need to change the math here!
          */

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
          let label = String(format: "%@ result==%.1f", bestClass, confidence * 100)
          print(bestClass);
          let color = colors[bestClass] ?? UIColor.red
          boundingBoxViews[i].show(frame: rect, label: label, color: color)
        } else {
          boundingBoxViews[i].hide()
        }
      }
    }
}

extension CameraDetect: videoCaptureDelegate {
  func videoCapture(_ capture: videoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
    predict(sampleBuffer: sampleBuffer)
  }
}

extension CameraDetect: RecordFileDelegate {
    
    func eventVideoRecorderDidSavedVideo(_ recorder: RecordFile) {

        
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
