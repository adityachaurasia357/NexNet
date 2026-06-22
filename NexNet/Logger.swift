//
//  Logger.swift
//  NexNet
//

import Foundation
import os.log

// MARK: - LogLevel

/// Severity levels for the NexNet logger, ordered from least to most severe.
///
/// Set `NexNetLogger.shared.minimumLevel` to filter out levels below a threshold.
/// Use `.none` to suppress all output.
public enum LogLevel: Int, Comparable, Sendable {
    /// Fine-grained diagnostic information; highest verbosity.
    case verbose = 0
    /// Standard developer diagnostics; the default minimum level.
    case debug   = 1
    /// Notable operational events that are not errors.
    case info    = 2
    /// Unexpected situations that did not prevent the operation from completing.
    case warning = 3
    /// Failures that require attention.
    case error   = 4
    /// Disables all log output.
    case none    = 5

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbol: String {
        switch self {
        case .verbose: return "[VERBOSE]"
        case .debug:   return "[DEBUG]"
        case .info:    return "[INFO]"
        case .warning: return "[WARNING]"
        case .error:   return "[ERROR]"
        case .none:    return ""
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug: return .debug
        case .info:            return .info
        case .warning:         return .default
        case .error:           return .error
        case .none:            return .default
        }
    }
}

// MARK: - Protocol

/// Interface for a NexNet-compatible logger.
///
/// Conform to this protocol to supply a custom logging back-end (e.g. a remote
/// analytics service) in place of the default `NexNetLogger`.
public protocol NexNetLoggerProtocol: Sendable {
    /// Logs a message at the specified severity level.
    ///
    /// - Parameters:
    ///   - message: The log message string.
    ///   - level: Severity of the event.
    ///   - file: Source file name (populated automatically via `#file`).
    ///   - function: Enclosing function name (populated automatically via `#function`).
    ///   - line: Source line number (populated automatically via `#line`).
    func log(_ message: String, level: LogLevel, file: String, function: String, line: Int)
}

// MARK: - NexNetLogger

/// Thread-safe structured logger backed by `os.log`.
///
/// **Release behaviour:** `isEnabled` defaults to `false` in release builds — logging
/// is compiled in but produces no output unless explicitly turned on. Console output
/// (`print`) is additionally guarded by `#if DEBUG`, so it never reaches the console
/// in release even when `isEnabled` is `true`; those builds route to `os_log` only.
public final class NexNetLogger: NexNetLoggerProtocol, @unchecked Sendable {
    public static let shared = NexNetLogger()

    private let osLog: OSLog
    private let lock = NSLock()

    // Default: on in DEBUG, off in RELEASE.
    private var _isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private var _minimumLevel: LogLevel = .debug

    /// Master on/off switch. In DEBUG builds this defaults to `true`; in RELEASE to `false`.
    public var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    /// Minimum level for the general `log(_:level:)` method. Does not affect `logCall`.
    public var minimumLevel: LogLevel {
        get { lock.withLock { _minimumLevel } }
        set { lock.withLock { _minimumLevel = newValue } }
    }

    public init(subsystem: String = "com.nexnet.framework") {
        self.osLog = OSLog(subsystem: subsystem, category: "networking")
    }

    // MARK: General logging

    /// Logs a message at the specified level if logging is enabled and the level meets the minimum threshold.
    ///
    /// In release builds, output goes to `os_log` only. In debug builds it also prints to the console.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - level: Severity level; filtered against `minimumLevel`.
    ///   - file: Auto-filled by the compiler.
    ///   - function: Auto-filled by the compiler.
    ///   - line: Auto-filled by the compiler.
    public func log(
        _ message: String,
        level: LogLevel,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled, level >= minimumLevel else { return }
        let filename = (file as NSString).lastPathComponent
        let formatted = "\(level.symbol) [NexNet] \(filename):\(line) — \(message)"
        os_log("%{public}@", log: osLog, type: level.osLogType, formatted)
        #if DEBUG
        print(formatted)
        #endif
    }

    // MARK: - Network Call Log

    /// Emits the structured box-format log for a completed network call.
    ///
    /// Called once per call (after all retry attempts), regardless of success or failure.
    /// `print` output is compiled out in release builds (`#if DEBUG`);
    /// `os_log` runs in all builds whenever `isEnabled == true`.
    func logCall(
        id: UUID,
        request: URLRequest,
        statusCode: Int?,
        responseData: Data?,
        error: (any Error)?,
        duration: TimeInterval
    ) {
        guard isEnabled else { return }

        let method     = request.httpMethod ?? "GET"
        let url        = request.url?.absoluteString ?? "unknown"
        let headersStr = formatHeaders(request.allHTTPHeaderFields ?? [:])
        let bodyStr    = request.httpBody.flatMap { prettyJSON(from: $0) } ?? "nil"
        let statusStr  = statusCode.map { String($0) } ?? "N/A"
        let responseStr: String
        if let error {
            responseStr = "Error — \(error.localizedDescription)"
        } else if let data = responseData, !data.isEmpty {
            responseStr = prettyJSON(from: data) ?? String(data: data, encoding: .utf8) ?? "nil"
        } else {
            responseStr = "nil"
        }
        let curlStr      = curlCommand(for: request)
        let durationStr  = String(format: "%.1fms", duration * 1000)

        let entry = """

        ┌─ [NexNet] Call ID: \(id.uuidString)
        ├─ URL: \(url)
        ├─ Method: \(method)
        ├─ Headers: \(indent(headersStr))
        ├─ Body: \(indent(bodyStr))
        ├─ Status: \(statusStr)
        ├─ Response: \(indent(responseStr))
        ├─ cURL: \(curlStr)
        └─ Duration: \(durationStr)
        """

        os_log("%{public}@", log: osLog, type: .debug, entry)
        #if DEBUG
        print(entry)
        #endif
    }
}

// MARK: - Convenience level shortcuts

extension NexNetLogger {
    func verbose(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(msg, level: .verbose, file: file, function: function, line: line)
    }
    func debug(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(msg, level: .debug, file: file, function: function, line: line)
    }
    func info(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(msg, level: .info, file: file, function: function, line: line)
    }
    func warning(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(msg, level: .warning, file: file, function: function, line: line)
    }
    func error(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(msg, level: .error, file: file, function: function, line: line)
    }
}

// MARK: - Private helpers

private extension NexNetLogger {

    /// Pretty-prints JSON data; returns `nil` if `data` is not valid JSON.
    func prettyJSON(from data: Data) -> String? {
        guard
            let obj   = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
            let str   = String(data: pretty, encoding: .utf8)
        else { return nil }
        return str
    }

    /// Formats a headers dictionary as an indented multi-line block.
    func formatHeaders(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "[:]" }
        let pairs = headers
            .sorted { $0.key < $1.key }
            .map { "    \"\($0.key)\": \"\($0.value)\"" }
            .joined(separator: ",\n")
        return "{\n\(pairs)\n  }"
    }

    /// Indents every line after the first so multi-line values stay visually inside the box.
    func indent(_ str: String) -> String {
        let lines = str.components(separatedBy: "\n")
        guard lines.count > 1 else { return str }
        let tail = lines.dropFirst().map { "│    \($0)" }.joined(separator: "\n")
        return "\(lines[0])\n\(tail)"
    }

    /// Builds a fully copy-pasteable `curl` command from a `URLRequest`.
    ///
    /// - Header values with internal `"` are backslash-escaped.
    /// - Body and URL single-quotes are shell-escaped using the `'\''` idiom.
    func curlCommand(for request: URLRequest) -> String {
        var parts: [String] = ["curl -sS"]

        parts.append("-X \(request.httpMethod ?? "GET")")

        request.allHTTPHeaderFields?
            .sorted { $0.key < $1.key }
            .forEach { key, value in
                let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
                parts.append("-H \"\(key): \(escaped)\"")
            }

        if let body = request.httpBody,
           let bodyStr = String(data: body, encoding: .utf8),
           !bodyStr.isEmpty {
            let escaped = bodyStr.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("--data-raw '\(escaped)'")
        }

        if let url = request.url {
            let escaped = url.absoluteString.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("'\(escaped)'")
        }

        return parts.joined(separator: " ")
    }
}
