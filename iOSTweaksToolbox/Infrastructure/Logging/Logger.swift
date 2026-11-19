//
//  Logger.swift
//  iOSTweaksToolbox
//
//  轻量 App 内日志门面，方便各处统一记录。
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
