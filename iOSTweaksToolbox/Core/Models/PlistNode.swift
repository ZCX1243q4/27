//
//  PlistNode.swift
//  iOSTweaksToolbox
//
//  可编辑的 plist 视图模型：把 Any 树映射成可绑定的节点树，
//  编辑后再还原成 Any 写回文件。
//

import Foundation
import SwiftUI
import Observation
import CoreFoundation

enum PlistValueType: String, CaseIterable, Identifiable, Codable {
    case dictionary = "Dictionary"
    case array = "Array"
    case string = "String"
    case integer = "Integer"
    case real = "Real"
    case boolean = "Boolean"
    case date = "Date"
    case data = "Data"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dictionary: return "square.grid.2x2"
        case .array: return "list.number"
        case .string: return "textformat"
        case .integer: return "number"
        case .real: return "function"
        case .boolean: return "switch.2"
        case .date: return "calendar"
        case .data: return "cylinder.split.1x2"
        }
    }
}

@Observable
final class PlistNode: Identifiable {
    let id = UUID()
    var key: String
    var type: PlistValueType
    var stringValue: String
    var boolValue: Bool
    var dateValue: Date
    var dataValue: Data
    var children: [PlistNode]
    var isExpanded: Bool = true

    init(key: String = "", value: Any) {
        self.key = key
        switch value {
        case let dict as [String: Any]:
            type = .dictionary
            stringValue = ""
            boolValue = false
            dateValue = Date()
            dataValue = Data()
            children = dict.keys.sorted().map { PlistNode(key: $0, value: dict[$0] as Any) }
        case let array as [Any]:
            type = .array
            stringValue = ""
            boolValue = false
            dateValue = Date()
            dataValue = Data()
            children = array.enumerated().map { PlistNode(key: "\($0.offset)", value: $0.element) }
        case let string as String:
            type = .string; stringValue = string; boolValue = false
            dateValue = Date(); dataValue = Data(); children = []
        case let bool as Bool:
            type = .boolean; stringValue = ""; boolValue = bool
            dateValue = Date(); dataValue = Data(); children = []
        case let number as NSNumber:
            // NSNumber 里 Boolean 与整数共用，靠 CFGetTypeID 区分
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                type = .boolean; boolValue = number.boolValue; stringValue = ""
            } else if String(cString: number.objCType) == "d" || String(cString: number.objCType) == "f" {
                type = .real; stringValue = "\(number.doubleValue)"; boolValue = false
            } else {
                type = .integer; stringValue = "\(number.int64Value)"; boolValue = false
            }
            dateValue = Date(); dataValue = Data(); children = []
        case let date as Date:
            type = .date; dateValue = date; stringValue = ""; boolValue = false
            dataValue = Data(); children = []
        case let data as Data:
            type = .data; dataValue = data; stringValue = ""; boolValue = false
            dateValue = Date(); children = []
        default:
            type = .string; stringValue = String(describing: value); boolValue = false
            dateValue = Date(); dataValue = Data(); children = []
        }
    }

    /// 还原成可序列化的 Any。
    func toAny() -> Any {
        switch type {
        case .dictionary:
            var dict: [String: Any] = [:]
            for child in children where !child.key.isEmpty {
                dict[child.key] = child.toAny()
            }
            return dict
        case .array:
            return children.map { $0.toAny() }
        case .string:
            return stringValue
        case .integer:
            return Int64(stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        case .real:
            return Double(stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        case .boolean:
            return boolValue
        case .date:
            return dateValue
        case .data:
            return dataValue
        }
    }

    /// 切换类型时尽量保留已有内容。
    func convert(to newType: PlistValueType) {
        guard newType != type else { return }
        let oldAny = toAny()
        type = newType
        switch newType {
        case .dictionary:
            children = []
        case .array:
            children = []
        case .string:
            stringValue = PlistService.preview(of: oldAny)
            children = []
        case .integer:
            if let number = oldAny as? NSNumber { stringValue = "\(number.int64Value)" }
            else { stringValue = "0" }
            children = []
        case .real:
            if let number = oldAny as? NSNumber { stringValue = "\(number.doubleValue)" }
            else { stringValue = "0.0" }
            children = []
        case .boolean:
            boolValue = (oldAny as? Bool) ?? false
            children = []
        case .date:
            dateValue = (oldAny as? Date) ?? Date()
            children = []
        case .data:
            dataValue = (oldAny as? Data) ?? Data()
            children = []
        }
    }

    func addChild() {
        switch type {
        case .dictionary:
            children.append(PlistNode(key: "NewKey", value: ""))
        case .array:
            children.append(PlistNode(key: "\(children.count)", value: ""))
        default:
            break
        }
    }

    func removeChild(id: UUID) {
        children.removeAll { $0.id == id }
        if type == .array {
            for (index, child) in children.enumerated() { child.key = "\(index)" }
        }
    }

    func child(matchingKey key: String) -> PlistNode? {
        children.first { $0.key == key }
    }
}
