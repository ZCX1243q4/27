//
//  IdentityModels.swift
//  iOSTweaksToolbox
//
//  设备身份配置模型。所有字段都是"目标值"，不是系统实际返回的值。
//

import Foundation

struct IdentityTarget: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var displayName: String
    var enabled: Bool = false

    var marketingName: String = ""
    var productType: String = ""
    var architecture: String = "arm64e"
    var systemVersion: String = ""
    var buildNumber: String = ""

    var logicalWidth: Double = 0
    var logicalHeight: Double = 0
    var nativeWidth: Double = 0
    var nativeHeight: Double = 0
    var scale: Double = 0

    var note: String = ""
    var updatedAt: Date = Date()
}

/// 一个 App 能拿到的真实身份，用于与目标值逐项对照。
struct RealIdentity: Codable {
    var marketingName: String
    var productType: String
    var architecture: String
    var systemVersion: String
    var buildNumber: String
    var logicalWidth: Double
    var logicalHeight: Double
    var nativeWidth: Double
    var nativeHeight: Double
    var scale: Double
}

struct IdentityComparisonRow: Identifiable {
    var id = UUID()
    var field: String
    var realValue: String
    var targetValue: String

    var matches: Bool { realValue == targetValue }
}
