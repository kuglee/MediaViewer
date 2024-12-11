//
//  AppDelegate.swift
//  MediaViewerDemo
//
//  Created by Yusaku Nishi on 2023/02/19.
//

import UIKit

//@main
//class AppDelegate: UIResponder, UIApplicationDelegate {
//    
//    func application(
//        _ application: UIApplication,
//        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//    ) -> Bool {
//        true
//    }
//    
//    // MARK: UISceneSession Lifecycle
//    
//    func application(
//        _ application: UIApplication,
//        configurationForConnecting connectingSceneSession: UISceneSession,
//        options: UIScene.ConnectionOptions
//    ) -> UISceneConfiguration {
//        UISceneConfiguration(
//            name: "Default Configuration",
//            sessionRole: connectingSceneSession.role
//        )
//    }
//}


import SwiftUI

@main
public struct SwiftUIApp: App {
  let remoteImages: [RemoteImage] = [
    .init(
//      image:
//        "https://localhost/_imgcache/gallery/timeline/24/i/eaaucjqyybguhflzannskuufanslza~200~200.jpg",
      image: "https://localhost/gallery/timeline/24/i/eaaucjqyybguhflzannskuufanslza.jpg",
      imagefull: "https://localhost/gallery/timeline/24/i/eaaucjqyybguhflzannskuufanslza.jpg"
    ),
    .init(
      image:
        "https://localhost/_imgcache/gallery/timeline/24/y/ixtpddqhfzpwtgqdyrtblkeynsuaij~200~200.jpg",
      imagefull: "https://localhost/gallery/timeline/24/y/ixtpddqhfzpwtgqdyrtblkeynsuaij.jpg"
    ),
    .init(
      image:
        "https://localhost/_imgcache/gallery/timeline/312/i/dcpwzldzwqnkgvylcrumybwmpzuhmm~200~200.jpg",
      imagefull: "https://localhost/gallery/timeline/312/i/dcpwzldzwqnkgvylcrumybwmpzuhmm.jpg"
    ),
    .init(
      image:
        "https://localhost/_imgcache/gallery/timeline/312/i/vwdhlrtygisjyeuqrblnvbrbjyxhjz~200~200.jpg",
      imagefull: "https://localhost/gallery/timeline/312/i/vwdhlrtygisjyeuqrblnvbrbjyxhjz.jpg"
    ),
  ]

  public init() {}

  public var body: some Scene {
    WindowGroup {
      NavigationStack {
        Test(remoteImages: self.remoteImages)
          .navigationTitle("Test")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }
}

struct Test: UIViewControllerRepresentable {
  let remoteImages: [RemoteImage]

  init(remoteImages: [RemoteImage]) {
    self.remoteImages = remoteImages
  }

  func makeUIViewController(context: Context) -> NukeImagesViewController {
    NukeImagesViewController(remoteImages: self.remoteImages)
  }

  func updateUIViewController(_ viewController: NukeImagesViewController, context: Context) {
  }
}
