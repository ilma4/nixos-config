import AppKit
import CoreGraphics

@main
@MainActor
final class MacEQSessionWatcher: NSObject {
    private let bundleIdentifier = "com.jatingrewal.maceq"

    static func main() {
        let watcher = MacEQSessionWatcher()
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(
            watcher,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        notifications.addObserver(
            watcher,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notifications.addObserver(
            watcher,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        watcher.startMacEQIfActive()
        withExtendedLifetime(watcher) {
            RunLoop.main.run()
        }
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        startMacEQIfActive()
    }

    @objc private func sessionDidResignActive(_ notification: Notification) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            where !app.isTerminated {
            if !app.terminate() {
                NSLog("Unable to terminate MacEQ")
            }
        }
    }

    private func startMacEQIfActive() {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                  .contains(where: { !$0.isTerminated }),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
