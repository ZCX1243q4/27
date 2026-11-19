//
//  OSCompatibility.swift
//  iOSTweaksToolbox
//
//  iOS 版本与能力的对应关系。数值来自对公开行为的实测结论，
//  未验证的组合一律标注为"待研究"。
//

import Foundation
import UIKit

enum OSCompatibility {
    static var systemVersion: String { UIDevice.current.systemVersion }

    static var major: Int {
        Int(systemVersion.split(separator: ".").first ?? "0") ?? 0
    }

    static var build: String { DeviceInfoService.buildNumber() }

    /// worse_query 系列沙盒越界技术的已知窗口（来自上游仓库的实测结论）。
    static var sandboxEscapeWindow: String {
        "iOS 26.0 – 26.7.2 与 iOS 27.0 – 27.3 beta 1（24C5037i）；27.3 beta 2（24C5049d）起失效"
    }

    static var systemAreasReachable: Bool { major >= 27 }

    static var isPatchedBuild: Bool {
        // 27.3 beta 2 及之后：上游明确标注修复
        if major > 27 { return true }
        if major == 27 {
            let parts = systemVersion.split(separator: ".").compactMap { Int($0) }
            if parts.count >= 2, parts[1] > 3 { return true }
            if parts.count >= 2, parts[1] == 3 {
                // 27.3 beta 2 的 build 是 24C5049d，beta 1 是 24C5037i
                return build.lowercased() >= "24c5049"
            }
        }
        return false
    }

    static var model: String { DeviceInfoService.hardwareIdentifier() }

    static var isTargetDevice: Bool { model == "iPhone17,5" }
}

enum CapabilityStatus: String, Codable {
    case available = "可用"
    case conditional = "条件可用"
    case research = "仅模拟"
    case unavailable = "不可用"
}

struct Capability: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var status: CapabilityStatus
    var detail: String
}
