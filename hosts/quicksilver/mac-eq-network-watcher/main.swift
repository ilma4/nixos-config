import AppKit
import Dispatch
import Network

@main
@MainActor
final class MacEQNetworkWatcher {
    private let monitor = NWPathMonitor()
    private var wasConnected = false

    static func main() {
        let watcher = MacEQNetworkWatcher()
        watcher.monitor.pathUpdateHandler = { [weak watcher] path in
            DispatchQueue.main.async { @MainActor [weak watcher] in
                watcher?.handle(path)
            }
        }
        watcher.monitor.start(queue: DispatchQueue(label: "com.ilma4.mac-eq-network-watcher"))
        dispatchMain()
    }

    private func handle(_ path: NWPath) {
        let isConnected =
            path.status == .satisfied &&
            (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))

        defer { wasConnected = isConnected }
        guard isConnected && !wasConnected else { return }

        let bundleIdentifier = "com.jatingrewal.maceq"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                  .contains(where: { !$0.isTerminated }),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
