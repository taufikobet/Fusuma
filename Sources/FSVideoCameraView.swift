//
//  FSVideoCameraView.swift
//  Fusuma
//
//  Created by Brendan Kirchner on 3/18/16.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import UIKit
import AVFoundation
import MZTimerLabel
import CoreMotion

@objc protocol FSVideoCameraViewDelegate: class {
    func videoFinished(withFileURL fileURL: URL)
}

final class FSVideoCameraView: UIView {

    @IBOutlet weak var previewViewContainer: UIView!
    @IBOutlet weak var shotButton: CameraButton!
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var flipButton: UIButton!
    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var recordIndicator: UIView!
    @IBOutlet weak var placeholderTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var timerLabelTopConstraint: NSLayoutConstraint!

    var mzTimerLabel:MZTimerLabel {
        return MZTimerLabel(label: timerLabel, andTimerType: MZTimerLabelTypeStopWatch)
    }
    
    weak var delegate: FSVideoCameraViewDelegate? = nil
    
    var session: AVCaptureSession?
    var device: AVCaptureDevice?
    var audioDevice: AVCaptureDevice?
    var videoInput: AVCaptureDeviceInput?
    var audioInput: AVCaptureDeviceInput?
    var videoOutput: AVCaptureMovieFileOutput?
    var focusView: UIView?
    
    var flashOffImage: UIImage?
    var flashOnImage: UIImage?
    var videoStartImage: UIImage?
    var videoStopImage: UIImage?

    let motionManager: CMMotionManager = CMMotionManager()
    var videoOrientation:UIInterfaceOrientation = .portrait
    
    fileprivate var isRecording = false
    
    static func instance() -> FSVideoCameraView {
        
        return UINib(nibName: "FSVideoCameraView", bundle: Bundle(for: self.classForCoder())).instantiate(withOwner: self, options: nil)[0] as! FSVideoCameraView
    }
    
    func initialize() {
        
        if session != nil {
            
            return
        }
        
        self.backgroundColor = fusumaBackgroundColor
        
        self.isHidden = false
        
        // AVCapture
        session = AVCaptureSession()
        session?.sessionPreset = AVCaptureSessionPreset640x480

        for device in AVCaptureDevice.devices() {
            
            if let device = device as? AVCaptureDevice , device.position == AVCaptureDevicePosition.back {
                
                self.device = device
            }
        }

        for device in AVCaptureDevice.devices(withMediaType: AVMediaTypeAudio) {
            if let device = device as? AVCaptureDevice {
                self.audioDevice = device
            }
        }

        do {

            if let session = session {
                
                videoInput = try AVCaptureDeviceInput(device: device)
                audioInput = try AVCaptureDeviceInput(device: audioDevice)
                
                session.addInput(videoInput)
                session.addInput(audioInput)
                
                videoOutput = AVCaptureMovieFileOutput()
                let totalSeconds = 60.0 //Total Seconds of capture time
                let timeScale: Int32 = 30 //FPS
                
                let maxDuration = CMTimeMakeWithSeconds(totalSeconds, timeScale)
                
                videoOutput?.maxRecordedDuration = maxDuration
                videoOutput?.minFreeDiskSpaceLimit = 1024 * 1024 //SET MIN FREE SPACE IN BYTES FOR RECORDING TO CONTINUE ON A VOLUME
                
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }
                
                let videoLayer = AVCaptureVideoPreviewLayer(session: session)
                videoLayer?.frame = self.previewViewContainer.bounds
                videoLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
                
                self.previewViewContainer.layer.addSublayer(videoLayer!)
                
                session.startRunning()
                
            }
            
            // Focus View
            self.focusView         = UIView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
            let tapRecognizer      = UITapGestureRecognizer(target: self, action: #selector(FSVideoCameraView.focus(_:)))
            self.previewViewContainer.addGestureRecognizer(tapRecognizer)
            
        } catch {
            
        }
        
        
        let bundle = Bundle(for: self.classForCoder)
        
        flashOnImage = fusumaFlashOnImage != nil ? fusumaFlashOnImage : UIImage(named: "ic_flash_on", in: bundle, compatibleWith: nil)
        flashOffImage = fusumaFlashOffImage != nil ? fusumaFlashOffImage : UIImage(named: "ic_flash_off", in: bundle, compatibleWith: nil)
        let flipImage = fusumaFlipImage != nil ? fusumaFlipImage : UIImage(named: "ic_loop", in: bundle, compatibleWith: nil)
        videoStartImage = fusumaVideoStartImage != nil ? fusumaVideoStartImage : UIImage(named: "video_button", in: bundle, compatibleWith: nil)
        videoStopImage = fusumaVideoStopImage != nil ? fusumaVideoStopImage : UIImage(named: "video_button_rec", in: bundle, compatibleWith: nil)

        
        if(fusumaTintIcons) {
            flashButton.tintColor = fusumaBaseTintColor
            flipButton.tintColor  = fusumaBaseTintColor

            flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
            flipButton.setImage(flipImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
        } else {
            flashButton.setImage(flashOffImage, for: UIControlState())
            flipButton.setImage(flipImage, for: UIControlState())
        }
        
        flashConfiguration()        
    }
    
    public override func safeAreaInsetsDidChange() {
        if #available(iOS 11.0, *) {
            super.safeAreaInsetsDidChange()
            let topInset = self.safeAreaInsets.top
            if topInset > 0 {
                placeholderTopConstraint.constant += topInset
                timerLabelTopConstraint.constant += topInset
            }
        }
    }

    
    func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 5.0
        if motionManager.isAccelerometerAvailable {
            let queue = OperationQueue.main
            motionManager.startAccelerometerUpdates(to: queue, withHandler: {
                [weak self]  data, error in
                
                guard let data = data else {
                    return
                }
                
                let angle = (atan2(data.acceleration.y,data.acceleration.x))*180/M_PI
                
                //print(angle)
                
                if (fabs(angle)<=45) {
                    self?.videoOrientation = .landscapeLeft
                }
                else if ((fabs(angle)>45)&&(fabs(angle)<135)) {
                    if(angle>0){
                        self?.videoOrientation = .portraitUpsideDown
                    } else {
                        self?.videoOrientation = .portrait
                        
                    }
                } else {
                    self?.videoOrientation = .landscapeRight
                }
            })
        }
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self)
    }
    
    func startCamera() {
        
        let status = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        
        if status == AVAuthorizationStatus.authorized {
            
            session?.startRunning()
            setupMotionManager()
        } else if status == AVAuthorizationStatus.denied || status == AVAuthorizationStatus.restricted {
            
            session?.stopRunning()
            stopMotionManager()
        }
    }
    
    func stopCamera() {
        if self.isRecording {
            self.toggleRecording()
        }
        session?.stopRunning()
        stopMotionManager()
    }
    
    @IBAction func shotButtonPressed(_ sender: UIButton) {
        
        self.toggleRecording()
        
        if self.isRecording {
            stopMotionManager()
        }
    }
    
    func stopMotionManager() {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
    }

    func startAnimatingRecordIndicator() {
        recordIndicator.isHidden = false
        UIView.animate(withDuration: 0.75, delay: 0.0, options: .repeat, animations: {
            self.recordIndicator.alpha = 0.0
        }, completion: nil)
    }

    func stopAnimatingRecordIndicator() {
        recordIndicator.layer.removeAllAnimations()
        recordIndicator.isHidden = true
    }
    
    fileprivate func toggleRecording() {
        guard let videoOutput = videoOutput else {
            return
        }
        
        self.isRecording = !self.isRecording
        
        let shotImage: UIImage?
        if self.isRecording {
            shotImage = videoStopImage
            mzTimerLabel.start()
            startAnimatingRecordIndicator()
        } else {
            shotImage = videoStartImage
            mzTimerLabel.pause()
            mzTimerLabel.reset()
            stopAnimatingRecordIndicator()
        }
        
        if self.isRecording {
            let outputPath = "\(NSTemporaryDirectory())output.mov"
            let outputURL = URL(fileURLWithPath: outputPath)
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputPath) {
                do {
                    try fileManager.removeItem(atPath: outputPath)
                } catch {
                    print("error removing item at path: \(outputPath)")
                    self.isRecording = false
                    return
                }
            }
            self.flipButton.isEnabled = false
            self.flashButton.isEnabled = false
            videoOutput.startRecording(toOutputFileURL: outputURL, recordingDelegate: self)
        } else {
            videoOutput.stopRecording()
            self.flipButton.isEnabled = true
            self.flashButton.isEnabled = true
        }
        return
    }
    
    @IBAction func flipButtonPressed(_ sender: UIButton) {
        
        session?.stopRunning()
        
        do {
            
            session?.beginConfiguration()
            
            if let session = session {
                
                for input in session.inputs {
                    
                    session.removeInput(input as! AVCaptureInput)
                }
                
                let position = (videoInput?.device.position == AVCaptureDevicePosition.front) ? AVCaptureDevicePosition.back : AVCaptureDevicePosition.front
                
                for device in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) {
                    
                    if let device = device as? AVCaptureDevice , device.position == position {
                        
                        videoInput = try AVCaptureDeviceInput(device: device)
                        session.addInput(videoInput)
                        
                    }
                }

                for device in AVCaptureDevice.devices(withMediaType: AVMediaTypeAudio) {
                    if let device = device as? AVCaptureDevice {
                        audioInput = try AVCaptureDeviceInput(device: device)
                        session.addInput(audioInput)
                    }
                }
                
            }
            
            session?.commitConfiguration()
            
            
        } catch {
            
        }
        
        session?.startRunning()
    }
    
    @IBAction func flashButtonPressed(_ sender: UIButton) {
        
        do {
            
            if let device = device {
                
                try device.lockForConfiguration()

                if device.hasFlash {
                    let mode = device.flashMode

                    if mode == AVCaptureFlashMode.off {

                        device.flashMode = AVCaptureFlashMode.on
                        flashButton.setImage(flashOnImage, for: UIControlState())

                    } else if mode == AVCaptureFlashMode.on {

                        device.flashMode = AVCaptureFlashMode.off
                        flashButton.setImage(flashOffImage, for: UIControlState())
                    }
                }

                device.unlockForConfiguration()
                
            }
            
        } catch _ {
            
            flashButton.setImage(flashOffImage, for: UIControlState())
            return
        }
        
    }

}

extension FSVideoCameraView: AVCaptureFileOutputRecordingDelegate {
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        print("started recording to: \(fileURL)")
    }
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        print("finished recording to: \(outputFileURL)")
                
        exportVideo(withURL: outputFileURL, orientation: videoOrientation) { (url) in
            if let url = url {
                self.delegate?.videoFinished(withFileURL: url)
            }
        }
    }
    
}

extension FSVideoCameraView {
    
    func focus(_ recognizer: UITapGestureRecognizer) {
        
        let point = recognizer.location(in: self)
        let viewsize = self.bounds.size
        let newPoint = CGPoint(x: point.y/viewsize.height, y: 1.0-point.x/viewsize.width)
        
        let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        do {
            
            try device?.lockForConfiguration()
            
        } catch _ {
            
            return
        }
        
        if device?.isFocusModeSupported(AVCaptureFocusMode.autoFocus) == true {
            
            device?.focusMode = AVCaptureFocusMode.autoFocus
            device?.focusPointOfInterest = newPoint
        }
        
        if device?.isExposureModeSupported(AVCaptureExposureMode.continuousAutoExposure) == true {
            
            device?.exposureMode = AVCaptureExposureMode.continuousAutoExposure
            device?.exposurePointOfInterest = newPoint
        }
        
        device?.unlockForConfiguration()
        
        self.focusView?.alpha = 0.0
        self.focusView?.center = point
        self.focusView?.backgroundColor = UIColor.clear
        self.focusView?.layer.borderColor = UIColor.white.cgColor
        self.focusView?.layer.borderWidth = 1.0
        self.focusView!.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        self.addSubview(self.focusView!)
        
        UIView.animate(withDuration: 0.8, delay: 0.0, usingSpringWithDamping: 0.8,
                                   initialSpringVelocity: 3.0, options: UIViewAnimationOptions.curveEaseIn, // UIViewAnimationOptions.BeginFromCurrentState
            animations: {
                self.focusView!.alpha = 1.0
                self.focusView!.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }, completion: {(finished) in
                self.focusView!.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                self.focusView!.removeFromSuperview()
        })
    }
    
    func flashConfiguration() {
        
        do {
            
            if let device = device {
                
                try device.lockForConfiguration()

                if device.hasFlash {
                    device.flashMode = AVCaptureFlashMode.off
                    flashButton.setImage(flashOffImage, for: UIControlState())
                }
                
                device.unlockForConfiguration()
                
            }
            
        } catch _ {
            
            return
        }
    }
}

extension FSVideoCameraView {
    func exportVideo(withURL url: URL, orientation:UIInterfaceOrientation, completionHandler:@escaping (URL?)->()) {
        let asset = AVURLAsset(url: url)
        let exportSession = SDAVAssetExportSession(asset: asset)!
        let outputPath = NSTemporaryDirectory().appending("temp.mov")
        if FileManager.default.fileExists(atPath: outputPath) {
            try! FileManager.default.removeItem(atPath: outputPath)
        }
        exportSession.outputURL = URL(fileURLWithPath: outputPath)
        exportSession.outputFileType = AVFileTypeQuickTimeMovie
//        exportSession.shouldOptimizeForNetworkUse = true
        var size:CGSize = CGSize.zero
        if let naturalSize = asset.tracks(withMediaType: AVMediaTypeVideo).first?.naturalSize,
            let preferredTransform = asset.tracks(withMediaType: AVMediaTypeVideo).first?.preferredTransform
        {
            size = naturalSize
            if isVideoRotated90_270(preferredTransform: preferredTransform) {
                let flippedSize:CGSize = size
                size.width = flippedSize.height
                size.height = flippedSize.width
            }
        }
        
        exportSession.videoSettings = [
            AVVideoCodecKey: AVVideoCodecH264,
            
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            
            AVVideoCompressionPropertiesKey: [
                
                AVVideoAverageBitRateKey: 1216000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High41,
            ],
        ]
        
        exportSession.audioSettings = [
            AVFormatIDKey: NSNumber(value: Int32(kAudioFormatMPEG4AAC)),
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64000,
        ]
        
        
        exportSession.exportAsynchronously(with: orientation, completionHandler: {
            DispatchQueue.main.async {
                print(exportSession.status)
                switch exportSession.status {
                case .cancelled:
                    print("cancelled")
                case .failed:
                    print("failed")
                    completionHandler(nil)
                case .unknown:
                    print("unknown")
                case .completed:
                    if let outputURL = exportSession.outputURL {
                        completionHandler(outputURL)
                    }
                default: break
                }
            }
        })
    }
    
    func isVideoRotated90_270(preferredTransform: CGAffineTransform) -> Bool {
        
        var isRotated90_270 = false
        
        let t: CGAffineTransform = preferredTransform
        
        if t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0 {
            isRotated90_270 = true
        }
        
        if t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0  {
            isRotated90_270 = true
        }
        
        if t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0  {
            isRotated90_270 = false
        }
        
        if t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0 {
            isRotated90_270 = false
        }
        
        return isRotated90_270
    }
}


