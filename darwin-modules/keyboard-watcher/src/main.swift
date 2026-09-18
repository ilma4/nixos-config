import CoreFoundation
import Darwin
import Dispatch
import Foundation
import IOKit
import IOKit.hidsystem

/// Prepend a local timestamp to every log line so the watcher's output in
/// `/tmp/keyboard-watcher.log` is easy to follow.
private func log(_ message: String) {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "EEE MMM d HH:mm:ss z yyyy"

  fputs("\(formatter.string(from: Date())): \(message)\n", stderr)
  fflush(stderr)
}

/// One `hidutil`-style key remapping: a source HID usage rewritten to a
/// destination HID usage.
private struct KeyMapping: Sendable, CustomStringConvertible {
  let source: UInt64
  let destination: UInt64

  init(_ value: String) throws {
    let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      throw WatcherError("key mapping \(value.debugDescription) must be in <src>:<dst> form")
    }
    source = try parseUnsigned(String(parts[0]), name: "source HID usage")
    destination = try parseUnsigned(String(parts[1]), name: "destination HID usage")
  }

  var description: String {
    "0x\(String(source, radix: 16)) -> 0x\(String(destination, radix: 16))"
  }
}

private struct WatcherError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) { self.description = description }
}

private func parseUnsigned<T: FixedWidthInteger & UnsignedInteger>(
  _ value: String, name: String
) throws -> T {
  let isHex = value.hasPrefix("0x") || value.hasPrefix("0X")
  let digits = isHex ? String(value.dropFirst(2)) : value
  guard let number = UInt64(digits, radix: isHex ? 16 : 10) else {
    throw WatcherError("invalid \(name): \(value)")
  }
  guard let result = T(exactly: number) else {
    throw WatcherError("\(name) \(value) does not fit in the required integer size")
  }
  return result
}

// MARK: - Core Foundation helpers

private func numberValue(_ value: CFTypeRef?) -> Int64? {
  guard let value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }

  var result: Int64 = 0
  return CFNumberGetValue(unsafeDowncast(value, to: CFNumber.self), .sInt64Type, &result)
    ? result : nil
}

private func stringValue(_ value: CFTypeRef?) -> String? {
  guard let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }

  let string = unsafeDowncast(value, to: CFString.self) as String
  // Match CFStringGetCString's original handling of embedded NULs.
  return String(string.prefix { $0 != "\0" })
}

// MARK: - HID remapping

private enum ApplyResult {
  case applied       // At least one service accepted the mapping.
  case noServiceYet  // No matching service; retry.
  case failed        // Could not enumerate services or set any mapping.
}

/// Immutable state shared by the run-loop callback and background retries.
private final class State: Sendable {
  let vendorID: UInt32
  let productID: UInt32
  let mappings: [KeyMapping]

  var deviceID: String { String(format: "%04x:%04x", vendorID, productID) }

  init(arguments: [String]) throws {
    let program = URL(fileURLWithPath: arguments.first ?? "keyboard-watcher")
      .lastPathComponent

    guard arguments.count >= 4 else {
      throw WatcherError("usage: \(program) <vendor-id> <product-id> <src:dst>...")
    }

    vendorID = try parseUnsigned(arguments[1], name: "vendor ID")
    productID = try parseUnsigned(arguments[2], name: "product ID")
    mappings = try arguments.dropFirst(3).map(KeyMapping.init)
  }

  /// macOS discards mappings on disconnect; re-apply to every matching event service.
  func tryApply() -> ApplyResult {
    let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    guard let services = IOHIDEventSystemClientCopyServices(client) else {
      log("error: could not copy HID event services")
      return .failed
    }

    // hidutil uses signed 64-bit numbers; preserve all bits of each HID usage.
    let mapping = mappings.map {
      [
        "HIDKeyboardModifierMappingSrc": Int64(bitPattern: $0.source),
        "HIDKeyboardModifierMappingDst": Int64(bitPattern: $0.destination),
      ]
    } as CFArray
    var result = ApplyResult.noServiceYet

    for service in services as! [IOHIDServiceClient] {
      let vendor = numberValue(IOHIDServiceClientCopyProperty(service, "VendorID" as CFString))
      let product = numberValue(IOHIDServiceClientCopyProperty(service, "ProductID" as CFString))

      guard vendor == Int64(vendorID), product == Int64(productID) else { continue }

      if case .noServiceYet = result { result = .failed }
      let serviceDescription = stringValue(
        IOHIDServiceClientCopyProperty(service, "Product" as CFString)
      ) ?? "unknown service"

      if IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, mapping) {
        result = .applied
        log("applied \(mappings.count) key remapping(s) to service \"\(serviceDescription)\"")
      } else {
        log("error: IOHIDServiceClientSetProperty(\"UserKeyMapping\") returned false for service \"\(serviceDescription)\"")
        mappings.forEach { log("  not applied: \($0)") }
      }
    }

    return result
  }
}

private let retryAttempts = 25
private let retryInterval: TimeInterval = 0.2

/// Drain a matching iterator — required to re-arm the notification — and, if
/// it produced any matching IORegistry nodes, apply the remapping.
private func processMatches(_ state: State, iterator: io_iterator_t) {
  var count = 0
  while case let object = IOIteratorNext(iterator), object != 0 {
    count += 1
    IOObjectRelease(object)
  }

  guard count > 0 else { return }

  log("matching HID device connected (\(count) IORegistry node(s)); applying remap")

  guard case .noServiceYet = state.tryApply() else { return }

  let budgetDescription = Int(Double(retryAttempts) * retryInterval)
  log("event service not published yet; retrying for up to ~\(budgetDescription)s")

  DispatchQueue.global(qos: .utility).async {
    for _ in 0..<retryAttempts {
      Thread.sleep(forTimeInterval: retryInterval)
      guard case .noServiceYet = state.tryApply() else { return }
    }

    log("error: no HID event service matched \(state.deviceID) after ~\(budgetDescription)s; remap not applied")
  }
}

do {
  let state = try State(arguments: CommandLine.arguments)

  // Retain the state independently of Swift's local lifetime analysis. The
  // run loop normally never returns, and retry callbacks may still be alive
  // if the loop is explicitly stopped.
  let statePointer = Unmanaged.passRetained(state).toOpaque()

  let runLoop = CFRunLoopGetCurrent()
  guard let notifyPort = IONotificationPortCreate(kIOMainPortDefault) else {
    throw WatcherError("failed to create IONotificationPort")
  }
  defer { IONotificationPortDestroy(notifyPort) }

  guard let source = IONotificationPortGetRunLoopSource(notifyPort)?.takeUnretainedValue() else {
    throw WatcherError("notification port has no run-loop source")
  }

  CFRunLoopAddSource(runLoop, source, .defaultMode)
  defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }

  var iterator: io_iterator_t = 0
  let result = IOServiceAddMatchingNotification(
    notifyPort,
    kIOFirstMatchNotification,
    NSMutableDictionary(dictionary: [
      "IOProviderClass": "IOHIDDevice",
      "VendorID": Int64(state.vendorID),
      "ProductID": Int64(state.productID),
    ]) as CFMutableDictionary,
    { refCon, iterator in
      guard let refCon else { return }
      processMatches(Unmanaged<State>.fromOpaque(refCon).takeUnretainedValue(), iterator: iterator)
    },
    statePointer,
    &iterator
  )

  guard result == KERN_SUCCESS else {
    throw WatcherError("IOServiceAddMatchingNotification failed: \(String(result, radix: 16))")
  }

  log("watching for HID device \(state.deviceID)")
  state.mappings.forEach { log("will remap on connect: \($0)") }

  // Drain the initial iterator: this both arms the notification and applies
  // the remapping to a keyboard that is already connected at startup.
  processMatches(state, iterator: iterator)

  CFRunLoopRun()
} catch {
  log("error: \(error)")
  exit(EXIT_FAILURE)
}
