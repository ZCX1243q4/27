//
//  FileMeta.swift
//  iOSTweaksToolbox
//
//  文件的真实元信息与可读写判定。判断依据是真实的文件系统调用，
//  失败就是失败，不做任何"看起来成功"的修饰。
//

import Foundation

enum FileKind: String, Codable {
    case plistXML = "XML Plist"
    case plistBinary = "Binary Plist"
    case json = "JSON"
    case text = "Text"
    case binary = "Binary"
    case directory = "Directory"
    case unknown = "Unknown"

    var isPlist: Bool { self == .plistXML || self == .plistBinary }
}

struct FileMeta: Identifiable, Codable {
    var id = UUID()
    var path: String
    var name: String
    var kind: FileKind
    var size: Int64
    var modified: Date?
    var created: Date?
    var isDirectory: Bool
    var isSymlink: Bool
    var isReadable: Bool
    var isWritable: Bool
    var posixPermissions: String
    var sha256: String?
    var note: String?

    var url: URL { URL(fileURLWithPath: path) }
}

enum FileInspector {
    static func meta(for url: URL, withHash: Bool = false) -> FileMeta {
        let fm = FileManager.default
        let path = url.path
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)

        var attributes: [FileAttributeKey: Any] = [:]
        if exists { attributes = (try? fm.attributesOfItem(atPath: path)) ?? [:] }

        let type = attributes[.type] as? FileAttributeType
        let isSymlink = (type == .typeSymbolicLink)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let posix = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0

        let readable = exists ? fm.isReadableFile(atPath: path) : false
        let writable = exists ? fm.isWritableFile(atPath: path) : false

        var kind: FileKind = .unknown
        if exists {
            if isDir.boolValue {
                kind = .directory
            } else {
                kind = detectKind(url: url)
            }
        }

        var note: String?
        if !exists { note = "路径不存在" }
        else if !readable { note = "无读取权限（沙盒或文件权限拒绝）" }

        return FileMeta(path: path,
                        name: url.lastPathComponent,
                        kind: kind,
                        size: size,
                        modified: attributes[.modificationDate] as? Date,
                        created: attributes[.creationDate] as? Date,
                        isDirectory: isDir.boolValue,
                        isSymlink: isSymlink,
                        isReadable: readable,
                        isWritable: writable,
                        posixPermissions: String(format: "%03o", posix),
                        sha256: (withHash && !isDir.boolValue && readable) ? Hashing.sha256(of: url) : nil,
                        note: note)
    }

    static func detectKind(url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ext == "json" ? .json : .unknown
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 16)) ?? Data()
        if head.starts(with: Data("bplist00".utf8)) { return .plistBinary }
        if head.starts(with: Data("<?xml".utf8)) || head.starts(with: Data("<plist".utf8)) {
            // 进一步确认真的是 plist
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
               (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil {
                return .plistXML
            }
            return .text
        }
        if ext == "plist" {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
               (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil {
                return .plistXML
            }
        }
        if ext == "json" || head.first == UInt8(ascii: "{") || head.first == UInt8(ascii: "[") {
            return .json
        }
        let printable = head.allSatisfy { $0 == 9 || $0 == 10 || $0 == 13 || ($0 >= 32 && $0 < 127) }
        return printable ? .text : .binary
    }
}
