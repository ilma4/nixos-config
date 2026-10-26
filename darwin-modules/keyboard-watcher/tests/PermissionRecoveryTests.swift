import Foundation

private final class Scenario {
  var granted = false
  var grantDuringApply = false
  var connected = true
  var attempts = 0
  var effectiveRemaps = 0
  var timersCreated = 0
  var messages: [String] = []
  var tick: (@Sendable () -> Void)?

  lazy var recovery = PermissionRecovery(
    hasPermission: { self.granted },
    applyMappings: {
      guard self.connected else { return }
      self.attempts += 1
      // Model a setter that returns success even when the mapping is blocked.
      if self.granted { self.effectiveRemaps += 1 }
      if self.grantDuringApply { self.granted = true }
    },
    log: { self.messages.append($0) },
    schedule: { callback in
      precondition(self.tick == nil, "duplicate permission timer")
      self.timersCreated += 1
      self.tick = callback
      return { self.tick = nil }
    }
  )

  func advance(seconds: Int) {
    for _ in 0..<seconds { tick?() }
  }
}

@main
private struct PermissionRecoveryTests {
  static func main() {
    let delayed = Scenario()
    delayed.recovery.deviceConnected()
    delayed.advance(seconds: 60)
    precondition(delayed.attempts == 1 && delayed.effectiveRemaps == 0)
    precondition(delayed.messages.count == 1, "waiting must not flood logs")
    delayed.granted = true
    delayed.advance(seconds: 1)
    precondition(delayed.effectiveRemaps == 1, "grant must remap without reconnect")
    precondition(delayed.tick == nil, "polling must stop after grant")
    delayed.advance(seconds: 60)
    precondition(delayed.attempts == 2)

    let duringWrite = Scenario()
    duringWrite.grantDuringApply = true
    duringWrite.recovery.deviceConnected()
    precondition(duringWrite.effectiveRemaps == 0 && duringWrite.tick != nil)
    duringWrite.advance(seconds: 1)
    precondition(duringWrite.effectiveRemaps == 1, "grant during initial write must not be missed")

    let repeated = Scenario()
    for _ in 0..<10 { repeated.recovery.deviceConnected() }
    precondition(repeated.timersCreated == 1)
    repeated.granted = true
    repeated.advance(seconds: 1)
    precondition(repeated.effectiveRemaps == 1)

    let disconnected = Scenario()
    disconnected.recovery.deviceConnected()
    disconnected.connected = false
    disconnected.granted = true
    disconnected.advance(seconds: 1)
    precondition(disconnected.attempts == 1 && disconnected.tick == nil)
    disconnected.connected = true
    disconnected.recovery.deviceConnected()
    precondition(disconnected.effectiveRemaps == 1)

    let permitted = Scenario()
    permitted.granted = true
    permitted.recovery.deviceConnected()
    precondition(permitted.effectiveRemaps == 1 && permitted.timersCreated == 0)
    permitted.recovery.deviceConnected()
    precondition(permitted.effectiveRemaps == 2, "reconnect must still remap")
    permitted.granted = false
    permitted.recovery.deviceConnected()
    precondition(permitted.tick != nil, "reconnect after revocation must resume polling")
    permitted.granted = true
    permitted.recovery.deviceConnected()
    precondition(permitted.tick == nil && permitted.effectiveRemaps == 3)

    print("Permission recovery tests passed")
  }
}
