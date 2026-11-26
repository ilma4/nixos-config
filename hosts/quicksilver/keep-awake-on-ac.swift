import Darwin
import Dispatch
import Foundation
import IOKit.ps

private func log(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

private func isOnACPower() -> Bool {
  guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
    let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
  else { return false }
  return source as String == kIOPMACPowerKey
}

@discardableResult
private func setSleepDisabled(_ disabled: Bool) -> Bool {
  // SleepDisabled is system-wide, even if pmset is called with -c.
  let pmset = Process()
  pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
  pmset.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
  pmset.standardOutput = FileHandle.standardError
  do {
    try pmset.run()
    pmset.waitUntilExit()
    if pmset.terminationReason == .exit && pmset.terminationStatus == 0 { return true }
    log("pmset failed (status \(pmset.terminationStatus))")
  } catch {
    log("could not run pmset: \(error)")
  }
  return false
}

private func syncSleepPolicy() {
  if !setSleepDisabled(isOnACPower()) {
    setSleepDisabled(false)
    exit(EXIT_FAILURE)  // Let launchd restart the daemon.
  }
}

// Serialize updates and shutdown so no callback can re-disable sleep during cleanup.
let signalSources = [SIGTERM, SIGINT].map { sig -> DispatchSourceSignal in
  signal(sig, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
  source.setEventHandler {
    exit(setSleepDisabled(false) ? EXIT_SUCCESS : EXIT_FAILURE)
  }
  source.resume()
  return source
}

// The attach event covers the internal battery being discovered during early boot.
// Neither notification fires for ordinary charge-level updates.
for name in [kIOPSNotifyPowerSource, kIOPSNotifyAttach] {
  var token: Int32 = 0
  let status = notify_register_dispatch(name, &token, .main) { _ in syncSleepPolicy() }
  guard status == NOTIFY_STATUS_OK else {
    log("could not subscribe to \(name) (status \(status))")
    setSleepDisabled(false)
    exit(EXIT_FAILURE)
  }
}

// Register first so a power transition cannot be missed during startup.
DispatchQueue.main.async { syncSleepPolicy() }
dispatchMain()
