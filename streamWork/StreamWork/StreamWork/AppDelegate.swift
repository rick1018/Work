//
//  AppDelegate.swift
//  StreamWork
//
//  Created by Rick_hsu on 2021/9/15.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var mainViewController :UIViewController?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        mainViewController  = MainViewController()
        mainViewController?.view.backgroundColor = UIColor.white
        let navigationController = UINavigationController(rootViewController: mainViewController!)
        var backButton: UIBarButtonItem = UIBarButtonItem(title: "返回", style: UIBarButtonItem.Style.bordered, target: self, action: nil)
        navigationController.navigationBar.topItem?.backBarButtonItem = backButton
        let frame = UIScreen.main.bounds
        window = UIWindow(frame: frame)
        window!.rootViewController = navigationController
        window!.makeKeyAndVisible()
        return true
    }
}

