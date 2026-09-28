import AppKit
import CoreWLAN
import Dispatch
import Network

@main
@MainActor
final class MacEQNetworkWatcher: NSObject, CWEventDelegate {
    private let monitor = NWPathMonitor()
    private let wifiClient = CWWiFiClient.shared()
    private let excludedSSIDs: Set<String> = ["JetBrains-Guest", "JetBrains-Team"]
    private var wasAllowed = false

    static func main() {
        let watcher = MacEQNetworkWatcher()
        watcher.wifiClient.delegate = watcher
        do {
            try watcher.wifiClient.startMonitoringEvent(with: .ssidDidChange)
        } catch {
            NSLog("Unable to monitor Wi-Fi network changes: %@", String(describing: error))
        }
        watcher.monitor.pathUpdateHandler = { [weak watcher] path in
            DispatchQueue.main.async { @MainActor [weak watcher] in
                watcher?.handle(path)
            }
        }
        watcher.monitor.start(queue: DispatchQueue(label: "com.ilma4.mac-eq-network-watcher"))
        withExtendedLifetime(watcher) {
            dispatchMain()
        }
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self else { return }
            self.handle(self.monitor.currentPath)
        }
    }

    private func handle(_ path: NWPath) {
        let isConnected =
            path.status == .satisfied &&
            (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))

        let bundleIdentifier = "com.jatingrewal.maceq"
        // Check every Wi-Fi interface, even when Ethernet is the preferred route.
        let isExcluded = (wifiClient.interfaces() ?? []).contains { interface in
            guard let ssid = interface.ssid() else { return false }
            return excludedSSIDs.contains(ssid)
        }
        let isAllowed = isConnected && !isExcluded
        defer { wasAllowed = isAllowed }

        if isExcluded {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                where !app.isTerminated {
                if !app.terminate() {
                    NSLog("Unable to terminate MacEQ")
                }
            }
            return
        }

        guard isAllowed && !wasAllowed else { return }

        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                  .contains(where: { !$0.isTerminated }),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
