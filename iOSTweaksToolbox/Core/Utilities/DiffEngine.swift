//
//  DiffEngine.swift
//  iOSTweaksToolbox
//
//  两棵 PropertyList 对象树的逐键差异。只报告差异，不做任何自动删除。
//

import Foundation

enum DiffKind: String, Codable {
    case added = "新增"
    case removed = "删除"
    case changed = "修改"
}

struct DiffItem: Identifiable, Codable {
    var id = UUID()
    var path: String
    var kind: DiffKind
    var oldValue: String
    var newValue: String
}

enum DiffEngine {
    static func diff(old: Any?, new: Any?) -> [DiffItem] {
        var items: [DiffItem] = []
        walk(old: old, new: new, path: "", into: &items)
        return items
    }

    private static func walk(old: Any?, new: Any?, path: String, into items: inout [DiffItem]) {
        switch (old, new) {
        case (nil, nil):
            return
        case (nil, .some(let value)):
            items.append(DiffItem(path: path.isEmpty ? "/" : path, kind: .added,
                                  oldValue: "—", newValue: describe(value)))
        case (.some(let value), nil):
            items.append(DiffItem(path: path.isEmpty ? "/" : path, kind: .removed,
                                  oldValue: describe(value), newValue: "—"))
        case (.some(let a), .some(let b)):
            if let da = a as? [String: Any], let db = b as? [String: Any] {
                let keys = Set(da.keys).union(db.keys).sorted()
                for key in keys {
                    walk(old: da[key], new: db[key], path: path + "/" + key, into: &items)
                }
            } else if let aa = a as? [Any], let ab = b as? [Any] {
                let count = max(aa.count, ab.count)
                for index in 0..<count {
                    let lhs: Any? = index < aa.count ? aa[index] : nil
                    let rhs: Any? = index < ab.count ? ab[index] : nil
                    walk(old: lhs, new: rhs, path: path + "/[\(index)]", into: &items)
                }
            } else if describe(a) != describe(b) {
                items.append(DiffItem(path: path.isEmpty ? "/" : path, kind: .changed,
                                      oldValue: describe(a), newValue: describe(b)))
            }
        }
    }

    static func describe(_ value: Any) -> String {
        switch value {
        case let data as Data:
            return "<Data \(data.count) bytes>"
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let dict as [String: Any]:
            return "<Dictionary \(dict.count) keys>"
        case let array as [Any]:
            return "<Array \(array.count) items>"
        default:
            return String(describing: value)
        }
    }
}
