import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let badgeChannelName = "com.ptools.harvest/app_badge"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: badgeChannelName,
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        guard call.method == "setBadgeCount" else {
          result(FlutterMethodNotImplemented)
          return
        }

        let count = max(call.arguments as? Int ?? 0, 0)
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(count) { error in
            DispatchQueue.main.async {
              if let error = error {
                result(FlutterError(code: "BADGE_UPDATE_FAILED", message: error.localizedDescription, details: nil))
              } else {
                result(nil)
              }
            }
          }
        } else {
          UIApplication.shared.applicationIconBadgeNumber = count
          result(nil)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
