//
//  PlistService.swift
//  iOSTweaksToolbox
//
//  真实读写 plist。写入前由调用方先做快照，写入失败回滚。
//

import Foundation

enum PlistFormat: String, Codable, CaseIterable {
    case xml = "XML"
    case binary = "Binary"

    var serializationFormat: PropertyListSerialization.PropertyListFormat {
        self == .xml ? .xml : .binary
    }
}

struct PlistDocument {
    var root: Any
    var format: PlistFormat
    var sourceURL: URL?

    var formatDescription: String { format.rawValue }
}

enum PlistService {
    static func load(url: URL) throws -> PlistDocument {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try load(data: data, sourceURL: url)
    }

    static func load(data: Data) throws -> PlistDocument {
        try load(data: data, sourceURL: nil)
    }

    private static func load(data: Data, sourceURL: URL?) throws -> PlistDocument {
        var format = PropertyListSerialization.PropertyListFormat.xml
        do {
            let object = try PropertyListSerialization.propertyList(from: data,
                                                                    options: [],
                                                                    format: &format)
            return PlistDocument(root: object,
                                 format: format == .binary ? .binary : .xml,
                                 sourceURL: sourceURL)
        } catch {
            throw ToolboxError.parseFailed(error.localizedDescription)
        }
    }

    static func serialize(_ object: Any, format: PlistFormat) throws -> Data {
        // 先做一次合法性检查，避免把非法对象写出去
        _ = try validate(object)
        do {
            return try PropertyListSerialization.data(fromPropertyList: object,
                                                      format: format.serializationFormat,
                                                      options: 0)
        } catch {
            throw ToolboxError.parseFailed(error.localizedDescription)
        }
    }

    /// 写入前的合法性检查：能序列化、能再解析回来、两者等价。
    static func validate(_ object: Any) throws -> Bool {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: object,
                                                      format: .xml,
                                                      options: 0)
        } catch {
            throw ToolboxError.parseFailed("对象无法序列化为 plist：\(error.localizedDescription)")
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard (try? PropertyListSerialization.propertyList(from: data,
                                                            options: [],
                                                            format: &format)) != nil else {
            throw ToolboxError.parseFailed("序列化结果无法再次解析")
        }
        return true
    }

    /// 带快照的写入。
    static func save(object: Any,
                     to url: URL,
                     format: PlistFormat,
                     backups: BackupService) throws {
        try PathGuard.check(url.path)
        let data = try serialize(object, format: format)
        let existing = FileManager.default.fileExists(atPath: url.path)
        var snapshot: BackupRecord?
        if existing { snapshot = try backups.snapshot(url: url, note: "保存前自动快照") }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            if let snapshot { _ = try? backups.restore(snapshot) }
            throw error
        }
    }

    // MARK: - 类型转换辅助

    static func typeName(of value: Any) -> String {
        switch value {
        case is [String: Any]: return "Dictionary"
        case is [Any]: return "Array"
        case is String: return "String"
        case is Bool: return "Boolean"
        case is Int, is Int64, is Int32: return "Integer"
        case is Double, is Float: return "Real"
        case is Date: return "Date"
        case is Data: return "Data"
        default: return String(describing: type(of: value))
        }
    }

    static func preview(of value: Any, limit: Int = 120) -> String {
        switch value {
        case let dict as [String: Any]: return "Dictionary · \(dict.count) 项"
        case let array as [Any]: return "Array · \(array.count) 项"
        case let data as Data: return "Data · \(data.count) 字节"
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let string as String:
            return string.count > limit ? String(string.prefix(limit)) + "…" : string
        default: return String(describing: value)
        }
    }

    /// 在对象树里按键或值做搜索，返回命中路径。
    static func search(_ root: Any, query: String, searchValues: Bool) -> [String] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        var hits: [String] = []
        func walk(_ node: Any, path: String) {
            if let dict = node as? [String: Any] {
                for key in dict.keys.sorted() {
                    let childPath = path + "/" + key
                    if key.lowercased().contains(needle) { hits.append(childPath) }
                    walk(dict[key] as Any, path: childPath)
                }
            } else if let array = node as? [Any] {
                for (index, child) in array.enumerated() {
                    walk(child, path: path + "/[\(index)]")
                }
            } else if searchValues, preview(of: node).lowercased().contains(needle) {
                hits.append(path.isEmpty ? "/" : path)
            }
        }
        walk(root, path: "")
        return hits
    }
}
