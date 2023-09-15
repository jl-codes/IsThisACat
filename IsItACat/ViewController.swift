//
//  ViewController.swift
//  IsItACat
//
//  Created by Tony Loehr on 9/15/23.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {

    // MARK: - UI Components
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Vision Properties
    var detectionRequest: VNCoreMLRequest?
    var detectionModel: VNCoreMLModel?
    var previousBoundingBox: CGRect?
    var detectionsCounter = 0
    let boundingBoxTolerance: CGFloat = 0.1
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        checkCameraPermissionsAndSetup()
        setupModel()
    }
    
    // MARK: - Camera Permissions and Setup
    func checkCameraPermissionsAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.initiateCameraSetup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.initiateCameraSetup()
                    }
                }
            }
        default:
            // Handles cases: .denied, .restricted, and @unknown default
            return
        }
    }
    
    func initiateCameraSetup() {

        let captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }
    
    // MARK: - Model Setup
    func setupModel() {
        do {
            self.detectionModel = try VNCoreMLModel(for: YOLOv3FP16().model)
            
            if let model = self.detectionModel {
                self.detectionRequest = VNCoreMLRequest(model: model, completionHandler: handleDetection)
            }
        } catch {
            print("Model loading error :( - \(error)")
        }
    }
    
    // MARK: - Detection Handling
    func handleDetection(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }

        DispatchQueue.main.async {
            self.view.layer.sublayers?.removeSubrange(1...)
            
            for observation in results where observation is VNRecognizedObjectObservation {
                guard let recognizedObjectObservation = observation as? VNRecognizedObjectObservation else {
                    continue
                }

                if recognizedObjectObservation.labels.contains(where: { $0.identifier == "cat" && $0.confidence > 0.7 }) {
                    let boundingBox = recognizedObjectObservation.boundingBox
                    var color = UIColor.red

                    // Check if the cat is centered
                    if self.isCentered(boundingBox: boundingBox) {
                        if self.isBoundingBox(boundingBox, closeTo: self.previousBoundingBox) {
                            self.detectionsCounter += 1
                        } else {
                            self.detectionsCounter = 0
                        }

                        if self.detectionsCounter > 5 {
                            color = .green
                            print("centered")
                        }
                    }

                    self.drawBorder(for: boundingBox, color: color)
                    self.view.layer.addSublayer(self.createTextLayer(for: boundingBox))
                    self.previousBoundingBox = boundingBox
                }
            }
        }
    }
    
    // MARK: - Bounding Box Handling
    func isBoundingBox(_ box1: CGRect?, closeTo box2: CGRect?) -> Bool {
        guard let box1 = box1, let box2 = box2 else { return false }

        let isCloseInX = abs(box1.origin.x - box2.origin.x) < boundingBoxTolerance
        let isCloseInY = abs(box1.origin.y - box2.origin.y) < boundingBoxTolerance
        let isCloseInWidth = abs(box1.width - box2.width) < boundingBoxTolerance
        let isCloseInHeight = abs(box1.height - box2.height) < boundingBoxTolerance

        return isCloseInX && isCloseInY && isCloseInWidth && isCloseInHeight
    }
    
    func isCentered(boundingBox: CGRect) -> Bool {
        let centerX = boundingBox.origin.x + (boundingBox.width / 2)
        let centerY = boundingBox.origin.y + (boundingBox.height / 2)
        return (centerX > 0.4 && centerX < 0.6) && (centerY > 0.4 && centerY < 0.6)  // Assuming centered within 20% margin
    }
    
    func drawBorder(for boundingBox: CGRect, color: UIColor) {
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = CGRect(x: boundingBox.origin.x * view.bounds.width,
                                  y: (1 - boundingBox.origin.y - boundingBox.height) * view.bounds.height,
                                  width: boundingBox.width * view.bounds.width,
                                  height: boundingBox.height * view.bounds.height)
        shapeLayer.borderWidth = 4
        shapeLayer.borderColor = color.cgColor
        view.layer.addSublayer(shapeLayer)
    }
    
    func createTextLayer(for boundingBox: CGRect) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.string = "yes"
        textLayer.foregroundColor = UIColor.cyan.cgColor
        textLayer.fontSize = 24
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true // wrap the text if it doesn't fit

        // Center the text inside the bounding box
        let centeredY = (1 - boundingBox.origin.y - boundingBox.height / 2) * view.bounds.height - textLayer.fontSize / 2
        textLayer.frame = CGRect(x: boundingBox.origin.x * view.bounds.width,
                                 y: centeredY, // This will vertically center the text
                                 width: boundingBox.width * view.bounds.width,
                                 height: 40) // height of the text layer

        return textLayer
    }

}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            if let request = detectionRequest {
                try imageRequestHandler.perform([request])
            }
        } catch {
            print(error)
        }
    }
}
