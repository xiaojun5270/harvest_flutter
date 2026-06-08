import UIKit
import SwiftUI
import UserNotifications

@main
@MainActor
@objc class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private let appStore = HarvestNativeAppStore()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self

    let rootView = HarvestRootView().environmentObject(appStore)
    let hostingController = UIHostingController(rootView: rootView)
    hostingController.view.backgroundColor = UIColor.systemBackground

    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    self.window = window

    return true
  }
}

extension AppDelegate: UNUserNotificationCenterDelegate {}

enum HarvestBadge {
  static func setBadgeCount(_ count: Int) {
    let normalized = max(count, 0)
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(normalized)
    } else {
      UIApplication.shared.applicationIconBadgeNumber = normalized
    }
  }
}
