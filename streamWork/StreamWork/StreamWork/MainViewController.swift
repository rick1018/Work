//
//  ViewController.swift
//  StreamWork
//
//  Created by Rick_hsu on 2021/9/15.
//


import UIKit

class MainViewController: UIViewController {

    var camerabtn = UIButton()
    var localbtn  = UIButton()
    let camera    = CameraDetect()
    let local     = LocalVideoDecode()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        camerabtn = UIButton(frame: CGRect(x: 20, y: 64, width: 100, height: 50))
        camerabtn.backgroundColor = UIColor.blue;
        camerabtn.setTitle("相機辨識", for: .normal)
        camerabtn.addTarget(self, action:#selector(handleCamera), for: .touchUpInside)
        self.view.addSubview(camerabtn)
        
        localbtn = UIButton(frame: CGRect(x: camerabtn.frame.origin.x + camerabtn.frame.size.width + 10,
                                          y: camerabtn.frame.origin.y,
                                          width: camerabtn.frame.size.width,
                                          height: camerabtn.frame.size.height))
        localbtn.backgroundColor = UIColor.red
        localbtn.addTarget(self, action:#selector(handleLocal), for: .touchUpInside)
        localbtn.setTitle("本地端視頻", for: .normal)
        self.view.addSubview(localbtn)
        
        
    }
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    @objc func handleCamera(){
        self.navigationController?.pushViewController(camera, animated: true)
    }
    
    @objc func handleLocal(){
        self.navigationController?.pushViewController(local, animated: true)
    }
    
}

