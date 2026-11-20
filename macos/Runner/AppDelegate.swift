import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // A menu bar app keeps running with its window closed.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
