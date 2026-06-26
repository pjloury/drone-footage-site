// WallpaperLog.swift
// Lightweight, crash-resilient local logging for the wallpaper agent.
//
// Why a file logger (instead of just os_log): the crash we're chasing is an
// over-release SIGSEGV that happens "silently in the background". To diagnose
// it we need a durable, append-only trail of what the app was doing right
// before it died — survivable across a hard crash.
//
// Crash-survivability strategy:
//  - Every line is written straight to a FileHandle (handed to the kernel
//    immediately). Even if the process segfaults a microsecond later, the
//    bytes are already in the kernel's file buffer and reach disk.
//  - A C-level signal handler (write(2) on a raw fd — async-signal-safe)
//    appends one final "FATAL signal N" line, so we can tell a crash apart
//    from a clean quit, and timestamp it against the lifecycle trail.
//
// Log location:  ~/Library/Logs/AerialLandscapes/wallpaper.log

import Foundation
import Darwin

/// Raw fd used only by the async-signal-safe crash handler. Set once at startup.
private var gCrashFD: Int32 = -1

private func crashSignalHandler(_ sig: Int32) {
    if gCrashFD >= 0 {
        // Async-signal-safe: only write(2) on a constant message + fd.
        var line = "\n*** FATAL signal "
        line += String(sig)
        line += " — process crashed ***\n"
        _ = line.withCString { ptr in write(gCrashFD, ptr, strlen(ptr)) }
        fsync(gCrashFD)
    }
    // Restore default handler and re-raise so the OS still writes the .ips report.
    signal(sig, SIG_DFL)
    raise(sig)
}

final class WallpaperLog: @unchecked Sendable {

    static let shared = WallpaperLog()

    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "com.aeriallandscapes.wallpaperlog")
    private let isoFormatter: ISO8601DateFormatter

    let fileURL: URL

    private init() {
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AerialLandscapes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("wallpaper.log")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: fileURL)
        _ = try? h?.seekToEnd()
        handle = h

        // Open a raw fd for the crash handler and install signal traps.
        gCrashFD = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        for sig in [SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGTRAP, SIGFPE] {
            signal(sig, crashSignalHandler)
        }
    }

    /// Append one line. Synchronous to the kernel so it survives a crash.
    func log(_ category: String, _ message: String) {
        let line = "\(isoFormatter.string(from: Date())) [\(category)] \(message)\n"
        queue.sync {
            guard let data = line.data(using: .utf8), let handle else { return }
            try? handle.write(contentsOf: data)
        }
    }

    /// Resident memory footprint in MB (phys_footprint, what the system bills).
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }
}
