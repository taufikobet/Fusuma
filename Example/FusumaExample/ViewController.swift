//
//  ViewController.swift
//  Fusuma
//
//  Created by ytakzk on 01/31/2016.
//  Copyright (c) 2016 ytakzk. All rights reserved.
//

import UIKit

class ViewController: UIViewController, FusumaDelegate {
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var showButton: UIButton!
    
    @IBOutlet weak var fileUrlLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        showButton.layer.cornerRadius = 2.0
        self.fileUrlLabel.text = ""
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func showButtonPressed(_ sender: AnyObject) {
        // Show Fusuma
        let fusuma = FusumaViewController()
        fusuma.hasVideo = true
        //        fusumaCropImage = false
        
        fusuma.delegate = self
        self.present(fusuma, animated: true, completion: nil)
    }
    
    // MARK: FusumaDelegate Protocol
    func fusumaImageSelected(_ image: UIImage) {
        
        print("Image selected")
        imageView.image = image
    }
    
    func fusumaVideoCompleted(withFileURL fileURL: URL) {
        print("video completed and output to file: \(fileURL)")
        self.fileUrlLabel.text = "file output to: \(fileURL.absoluteString)"
    }

    func fusumaVideoCaptured(withFileURL fileURL: URL) {
        print("video completed and output to file: \(fileURL)")
        self.fileUrlLabel.text = "file output to: \(fileURL.absoluteString)"
        if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileURL.path) {
            UISaveVideoAtPathToSavedPhotosAlbum(fileURL.path, nil, nil, nil)
        }
    }

    func fusumaDismissedWithImage(_ image: UIImage) {
        
        print("Called just after dismissed FusumaViewController")
    }
    
    func fusumaCameraRollUnauthorized() {
        
        print("Camera roll unauthorized")
        
        let alert = UIAlertController(title: "Access Requested", message: "Saving image needs to access your photo album", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Settings", style: .default, handler: { (action) -> Void in
            
            if let url = URL(string:UIApplicationOpenSettingsURLString) {
                UIApplication.shared.openURL(url)
            }

        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
            
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func fusumaClosed() {
     
        print("Called when the close button is pressed")
    }

}

