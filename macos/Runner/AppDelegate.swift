import Cocoa
import Foundation
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // The headless `--bake-dir=…` flow runs entirely from Dart `main()` with
    // no real UI. AppKit's default behaviour for an app with no foreground
    // activity is to permit sudden + automatic termination, which kills the
    // bake mid-run. Disable both so a long batch can finish unattended.
    ProcessInfo.processInfo.disableSuddenTermination()
    ProcessInfo.processInfo.disableAutomaticTermination(
      "picture_book is running a headless task")
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Stay alive if the (hidden / unused) Flutter window closes — we may be
    // doing background work from Dart `main()`.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
