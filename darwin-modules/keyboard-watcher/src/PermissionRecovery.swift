import Foundation

/// All state and callbacks are confined to the main dispatch queue.
final class PermissionRecovery: @unchecked Sendable {
  private let hasPermission: () -> Bool
  private let applyMappings: () -> Void
  private let log: (String) -> Void
  private let schedule: (@escaping @Sendable () -> Void) -> () -> Void
  private var cancelTimer: (() -> Void)?

  init(
    hasPermission: @escaping () -> Bool,
    applyMappings: @escaping () -> Void,
    log: @escaping (String) -> Void,
    schedule: @escaping (@escaping @Sendable () -> Void) -> () -> Void = { callback in
      let timer = DispatchSource.makeTimerSource(queue: .main)
      timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
      timer.setEventHandler(handler: callback)
      timer.resume()
      return { timer.cancel() }
    }
  ) {
    self.hasPermission = hasPermission
    self.applyMappings = applyMappings
    self.log = log
    self.schedule = schedule
  }

  func deviceConnected() {
    dispatchPrecondition(condition: .onQueue(.main))
    if hasPermission() {
      cancelTimer?()
      cancelTimer = nil
    } else if cancelTimer == nil {
      log("waiting for Input Monitoring permission; checking every second")
      cancelTimer = schedule { [weak self] in self?.checkPermission() }
    }
    // Arm recovery before writing so a grant during the write cannot be missed.
    // Unrestricted mappings can work without permission, and the HID API may
    // report success for a restricted mapping too.
    applyMappings()
  }

  private func checkPermission() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard hasPermission() else { return }
    cancelTimer?()
    cancelTimer = nil
    log("Input Monitoring permission granted; retrying connected keyboard remap")
    applyMappings()
  }
}
