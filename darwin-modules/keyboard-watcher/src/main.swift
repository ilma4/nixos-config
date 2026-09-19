import Foundation
import IOKit
import IOKit.hidsystem

private func log(_ message: String) {
  FileHandle.standardError.write(Data("\(Date().ISO8601Format()): \(message)\n".utf8))
}

private struct WatcherError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) { self.description = description }
}

private func parseUnsigned<T: FixedWidthInteger & UnsignedInteger>(
  _ value: some StringProtocol, name: String
) throws -> T {
  let isHex = value.hasPrefix("0x") || value.hasPrefix("0X")
  let digits = isHex ? value.dropFirst(2) : value[...]
  guard let number = T(digits, radix: isHex ? 16 : 10) else {
    throw WatcherError("invalid or out-of-range \(name): \(value)")
  }
  return number
}

/// Immutable state shared by notification callbacks and background retries.
private final class KeyboardWatcher: Sendable {
  let device: [String: UInt32]
  let deviceID: String
  let mappings: [[String: Int64]]

  init(arguments: [String]) throws {
    guard arguments.count >= 4 else {
      throw WatcherError("usage: keyboard-watcher <vendor-id> <product-id> <src:dst>...")
    }

    let vendorID: UInt32 = try parseUnsigned(arguments[1], name: "vendor ID")
    let productID: UInt32 = try parseUnsigned(arguments[2], name: "product ID")
    device = ["VendorID": vendorID, "ProductID": productID]
    deviceID = String(format: "%04x:%04x", vendorID, productID)
    mappings = try arguments.dropFirst(3).map { value in
      let parts = value.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        throw WatcherError("key mapping \(value.debugDescription) must be in <src>:<dst> form")
      }
      // hidutil uses signed 64-bit numbers; preserve all bits of each HID usage.
      return try [
        "HIDKeyboardModifierMappingSrc": Int64(bitPattern: parseUnsigned(parts[0], name: "source HID usage")),
        "HIDKeyboardModifierMappingDst": Int64(bitPattern: parseUnsigned(parts[1], name: "destination HID usage")),
      ]
    }
  }

  /// macOS discards mappings on disconnect; re-apply to every matching event service.
  func applyMappings(retries: Int = 25) {
    let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
      log("error: could not copy HID event services")
      return
    }

    let matchingServices = services.filter { service in
      device.allSatisfy { key, value in
        let property = IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber
        return property?.int64Value == Int64(value)
      }
    }

    for service in matchingServices {
      let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String ?? "unknown service"

      if IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, mappings as CFArray) {
        log("applied \(mappings.count) key remapping(s) to service \"\(name)\"")
      } else {
        log("error: IOHIDServiceClientSetProperty(\"UserKeyMapping\") returned false for service \"\(name)\"")
      }
    }

    guard matchingServices.isEmpty else { return }
    guard retries > 0 else {
      log("error: no HID event service matched \(deviceID) after ~5s; remap not applied")
      return
    }
    // Event services can appear after the IORegistry notification.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { [self] in
      applyMappings(retries: retries - 1)
    }
  }

  /// Drain the iterator to re-arm notifications, then remap any matching services.
  func processMatches(_ iterator: io_iterator_t) {
    var count = 0
    while case let object = IOIteratorNext(iterator), object != 0 {
      count += 1
      IOObjectRelease(object)
    }

    guard count > 0 else { return }
    log("matching HID device connected (\(count) IORegistry node(s)); applying remap")
    applyMappings()
  }
}

do {
  let watcher = try KeyboardWatcher(arguments: CommandLine.arguments)

  // Keep the callback context alive until after notifications are torn down.
  defer { withExtendedLifetime(watcher) {} }

  guard let notifyPort = IONotificationPortCreate(kIOMainPortDefault) else {
    throw WatcherError("failed to create IONotificationPort")
  }
  defer { IONotificationPortDestroy(notifyPort) }

  IONotificationPortSetDispatchQueue(notifyPort, .main)

  var matching = watcher.device as [String: Any]
  matching["IOProviderClass"] = "IOHIDDevice"
  var iterator: io_iterator_t = 0
  let result = IOServiceAddMatchingNotification(
    notifyPort,
    kIOFirstMatchNotification,
    matching as CFDictionary,
    { refCon, iterator in
      guard let refCon else { return }
      Unmanaged<KeyboardWatcher>.fromOpaque(refCon).takeUnretainedValue().processMatches(iterator)
    },
    Unmanaged.passUnretained(watcher).toOpaque(),
    &iterator
  )

  guard result == KERN_SUCCESS else {
    throw WatcherError("IOServiceAddMatchingNotification failed: \(String(result, radix: 16))")
  }
  defer { IOObjectRelease(iterator) }

  log("watching for HID device \(watcher.deviceID)")
  log("key mappings: \(CommandLine.arguments.dropFirst(3).joined(separator: ", "))")

  // Drain the initial iterator: this both arms the notification and applies
  // the remapping to a keyboard that is already connected at startup.
  watcher.processMatches(iterator)

  dispatchMain()
} catch {
  log("error: \(error)")
  exit(EXIT_FAILURE)
}
