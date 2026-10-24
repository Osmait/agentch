import Foundation

/// Finds command-line tools. Apps launched from Finder get a minimal PATH,
/// so look in the usual install locations as well.
enum CLILocator {
    static func find(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = envPaths + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin"
        ]
        for directory in candidates {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

/// Talks newline-delimited JSON-RPC to a child process over stdin/stdout.
final class JSONLineProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func start() throws {
        try process.run()
    }

    func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(UInt8(ascii: "\n"))
        input.fileHandleForWriting.write(data)
    }

    /// Calls `handler` with each JSON object the process prints until it returns a value.
    /// Terminates the process when done or after `timeout` seconds.
    func read<T>(timeout: TimeInterval, until handler: ([String: Any]) throws -> T?) async throws -> T {
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        for try await line in output.fileHandleForReading.bytes.lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            if let result = try handler(object) { return result }
        }
        throw UsageError("The process exited without responding")
    }
}
