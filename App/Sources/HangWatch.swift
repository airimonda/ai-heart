import Foundation

/// Logs when the main thread stops answering for over half a second (diagnostics only:
/// a label and a duration, never content).
enum HangWatch {
    nonisolated(unsafe) static var label = "idle"

    static func start() {
        let q = DispatchQueue(label: "hangwatch", qos: .utility)
        q.async {
            while true {
                let sent = Date()
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                if sem.wait(timeout: .now() + 0.5) == .timedOut {
                    let what = label
                    sem.wait()
                    NSLog("AiHeartHang main blocked %.1f s during %@", Date().timeIntervalSince(sent), what)
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    static func mark<T>(_ l: String, _ f: () throws -> T) rethrows -> T {
        let old = label; label = l
        defer { label = old }
        return try f()
    }
}
