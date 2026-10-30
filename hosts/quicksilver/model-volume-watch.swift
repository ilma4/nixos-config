import Foundation

func checked(_ result: Int32, error: Int32 = errno) throws -> Int32 {
    if result == -1 { throw POSIXError(.init(rawValue: error) ?? .EIO) } else { result }
}

func run(_ args: [String]) throws -> Int32 {
    guard args.count >= 4 else {
        fputs("Usage: model-volume-watch VOLUME MODELS_DIRECTORY COMMAND [ARGUMENTS...]\n", stderr); return 1
    }
    let isMounted = { FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil)?
        .contains(URL(fileURLWithPath: args[1])) == true }
    // Ignore unrelated mounts; "/" requires a directory, including symlinks.
    guard isMounted(), !args[2].isEmpty, FileManager.default.fileExists(atPath: args[2] + "/") else { return 0 }

    let queue = try checked(kqueue())
    func watch(_ watches: (Int32, Int32, UInt32)..., poll: Bool = false) throws -> [Int32] {
        var events = Array(repeating: kevent(), count: 4)
        let count = try checked(kevent(queue, watches.map { id, filter, notes in
            .init(ident: UInt(id), filter: Int16(filter), flags: UInt16(EV_ADD), fflags: notes, data: 0, udata: nil)
        }, Int32(watches.count), &events, Int32(events.count), poll ? [timespec()] : nil))
        return try events.prefix(Int(count)).map {
            try checked($0.flags & UInt16(EV_ERROR) != 0 ? -1 : Int32($0.filter), error: Int32($0.data))
        }
    }
    let volumeFD = open(args[1], O_EVTONLY | O_CLOEXEC) // Allow unmounting while watching.
    if volumeFD == -1 && !isMounted() { return 0 }
    [SIGTERM, SIGINT].forEach { signal($0, SIG_IGN) }
    guard try watch((SIGTERM, EVFILT_SIGNAL, 0), (SIGINT, EVFILT_SIGNAL, 0),
                    (try checked(volumeFD), EVFILT_VNODE, UInt32(NOTE_REVOKE)), poll: true).isEmpty,
          isMounted() else { return 0 }

    // Process creates a group; env finds the command in PATH.
    let process = try Process.run(.init(fileURLWithPath: "/usr/bin/env"), arguments: ["--"] + args.dropFirst(3))
    let pid = process.processIdentifier
    defer {
        kill(-pid, SIGTERM)
        let deadline = DispatchTime.now() + 10
        while DispatchTime.now() < deadline && (kill(-pid, 0) == 0 || errno != ESRCH) { usleep(100_000) }
        kill(-pid, SIGKILL)
        process.waitUntilExit()
    }
    print("Model service started (pid \(pid))"); fflush(stdout)
    let filters = try watch((pid, EVFILT_PROC, NOTE_EXIT))
    if filters.contains(EVFILT_VNODE) { print("Model volume unmounted; stopping Model service") }
    return filters == [EVFILT_PROC] ? 1 : 0
}
do { exit(try run(CommandLine.arguments)) } catch { fputs("model-volume-watch: \(error)\n", stderr); exit(1) }
