//
//  Logger.swift
//  iOSTweaksToolbox
//

import Foundation

final class AppLogger {
    static let shared = AppLogger()
    weak var sink: EventLog?
    private init() {}

    func info(_ message: String) { sink?.append(.info, message) }
    func ok(_ message: String) { sink?.append(.success, message) }
    func warn(_ message: String) { sink?.append(.warning, message) }
    func error(_ message: String) { sink?.append(.error, message) }
}

extension EventLog {
    func info(_ message: String) { append(.info, message) }
    func ok(_ message: String) { append(.success, message) }
    func warn(_ message: String) { append(.warning, message) }
    func fail(_ message: String) { append(.error, message) }
}
