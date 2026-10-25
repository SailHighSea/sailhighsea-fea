import Cocoa
import FlutterMacOS
import UserNotifications

/// Lets bill reminders show as banners while the app is open (flutter_local_notifications).
/// A separate object, so the app delegate stays exactly as Flutter generates it.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  static let shared = ReminderNotificationDelegate()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The layouts start at 360 wide; do not let the window get smaller than that.
    self.minSize = NSSize(width: 360, height: 560)

    RegisterGeneratedPlugins(registry: flutterViewController)
    UNUserNotificationCenter.current().delegate = ReminderNotificationDelegate.shared

    super.awakeFromNib()
  }
}
