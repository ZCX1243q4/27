//
//  EventLog.swift
//  iOSTweaksToolbox
//

import Foundation
import Combine

enum LogLevel: String, Codable {
    case info, success, warning, error

    var label: String {
        switch self {
        case .info: return "INFO"
        case .success: return "OK"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

struct LogEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var level: LogLevel
    var message: String
}

final class EventLog: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    private let limit = 3000

    func append(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(level: level, message: message)
        if Thread.isMainThread {
            push(entry)
        } else {
            DispatchQueue.main.async { self.push(entry) }
        }
    }

    private func push(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    func clear() { entries.removeAll() }

    func text() -> String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            "[\(formatter.string(from: entry.date))] \(entry.level.label) \(entry.message)"
        }.joined(separator: "\n")
    }

    func export(to folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("TweaksToolbox-log-\(Self.stamp()).txt")
        try text().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
