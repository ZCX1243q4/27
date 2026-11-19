//
//  BackupService.swift
//  iOSTweaksToolbox
//
//  修改前的自动快照。写入流程：快照 -> 写入 -> 失败回滚。
//

import Foundation
import Combine

struct BackupRecord: Identifiable, Codable, Hashable {
    var id: String            // 目录名（时间戳 + 短哈希）
    var createdAt: Date
    var originalPath: String
    var storedName: String
    var size: Int64
    var sha256: String
    var note: String?
    var restoredAt: Date?
}

final class BackupService: ObservableObject {
    @Published private(set) var records: [BackupRecord] = []

    private let workspace: WorkspacePaths
    private var log: EventLog?
    private let fm = FileManager.default

    init(workspace: WorkspacePaths, log: EventLog?) {
        self.workspace = workspace
        self.log = log
        loadIndex()
    }

    func attachLog(_ log: EventLog) { self.log = log }

    // MARK: - 快照

    @discardableResult
    func snapshot(url: URL, note: String? = nil) throws -> BackupRecord {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = Hashing.sha256(data)
        let id = "\(EventLog.stamp())-\(digest.prefix(8))"
        let folder = workspace.backups.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let storedName = url.lastPathComponent.isEmpty ? "payload" : url.lastPathComponent
        let stored = folder.appendingPathComponent(storedName)
        try data.write(to: stored, options: .atomic)

        let record = BackupRecord(id: id,
                                  createdAt: Date(),
                                  originalPath: url.path,
                                  storedName: storedName,
                                  size: Int64(data.count),
                                  sha256: digest,
                                  note: note,
                                  restoredAt: nil)
        records.insert(record, at: 0)
        try saveIndex()
        log?.append(.info, "已创建快照 \(id)：\(url.path) (\(data.count) 字节)")
        return record
    }

    func storedURL(for record: BackupRecord) -> URL {
        workspace.backups.appendingPathComponent(record.id, isDirectory: true)
            .appendingPathComponent(record.storedName)
    }

    /// 校验快照内容仍与登记的一致。
    func verify(_ record: BackupRecord) -> Bool {
        let url = storedURL(for: record)
        guard let data = try? Data(contentsOf: url) else { return false }
        return Hashing.sha256(data) == record.sha256
    }

    /// 恢复到原始路径，并先给"当前内容"再做一次快照。
    @discardableResult
    func restore(_ record: BackupRecord) throws -> BackupRecord? {
        let target = URL(fileURLWithPath: record.originalPath)
        var safety: BackupRecord?
        if fm.fileExists(atPath: target.path) {
            safety = try snapshot(url: target, note: "恢复 \(record.id) 之前")
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        }
        guard verify(record) else { throw ToolboxError.checksumMismatch(record.id) }
        let data = try Data(contentsOf: storedURL(for: record))
        try data.write(to: target, options: .atomic)

        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index].restoredAt = Date()
            try saveIndex()
        }
        log?.append(.success, "已恢复 \(record.id) → \(record.originalPath)")
        return safety
    }

    func delete(_ record: BackupRecord) throws {
        try? fm.removeItem(at: workspace.backups.appendingPathComponent(record.id, isDirectory: true))
        records.removeAll { $0.id == record.id }
        try saveIndex()
    }

    // MARK: - 索引

    private var indexURL: URL { workspace.root.appendingPathComponent("backups-index.json") }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([BackupRecord].self, from: data)) ?? []
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: indexURL, options: .atomic)
    }
}

enum ToolboxError: LocalizedError {
    case checksumMismatch(String)
    case notWritable(String)
    case parseFailed(String)
    case unsupportedType(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let id): return "校验失败：快照 \(id) 的内容与登记哈希不一致"
        case .notWritable(let path): return "不可写：\(path)"
        case .parseFailed(let reason): return "解析失败：\(reason)"
        case .unsupportedType(let type): return "不支持的类型：\(type)"
        case .cancelled: return "已取消"
        }
    }
}
