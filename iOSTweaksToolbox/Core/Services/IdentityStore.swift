//
//  IdentityStore.swift
//  iOSTweaksToolbox
//
//  逐 App 的设备身份配置库。它只记录"目标值"，
//  不代表系统已经对目标 App 生效。
//

import Foundation
import Combine
import UIKit

struct IdentityDataset: Codable {
    var targets: [IdentityTarget] = []
}

final class IdentityStore: ObservableObject {
    @Published private(set) var targets: [IdentityTarget] = []

    private let workspace: WorkspacePaths
    private var dataURL: URL { workspace.profiles.appendingPathComponent("Identity/targets.json") }
    private let fm = FileManager.default

    init(workspace: WorkspacePaths) { self.workspace = workspace }

    func load() {
        guard let data = try? Data(contentsOf: dataURL) else {
            targets = Self.defaults
            try? persist()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        targets = (try? decoder.decode(IdentityDataset.self, from: data).targets) ?? Self.defaults
    }

    static var defaults: [IdentityTarget] {
        [
            IdentityTarget(bundleID: "com.tencent.xin", displayName: "微信"),
            IdentityTarget(bundleID: "com.apple.Preferences", displayName: "系统设置"),
            IdentityTarget(bundleID: "com.apple.mobilesafari", displayName: "Safari")
        ]
    }

    func persist() throws {
        try fm.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(IdentityDataset(targets: targets)).write(to: dataURL, options: .atomic)
    }

    func upsert(_ target: IdentityTarget) {
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            var updated = target
            updated.updatedAt = Date()
            targets[index] = updated
        } else {
            targets.append(target)
        }
        try? persist()
    }

    func remove(_ target: IdentityTarget) {
        targets.removeAll { $0.id == target.id }
        try? persist()
    }

    /// 读真实身份（本进程能拿到的公开值）。
    @MainActor
    static func realIdentity() -> RealIdentity {
        let screen = UIScreen.main
        let snapshot = DisplayService.snapshot()
        return RealIdentity(marketingName: DeviceInfoService.marketingName(for: DeviceInfoService.hardwareIdentifier()),
                            productType: DeviceInfoService.hardwareIdentifier(),
                            architecture: DeviceInfoService.architecture(),
                            systemVersion: UIDevice.current.systemVersion,
                            buildNumber: DeviceInfoService.buildNumber(),
                            logicalWidth: Double(screen.bounds.width),
                            logicalHeight: Double(screen.bounds.height),
                            nativeWidth: snapshot.nativeBoundsWidth,
                            nativeHeight: snapshot.nativeBoundsHeight,
                            scale: Double(screen.scale))
    }

    static func comparison(real: RealIdentity, target: IdentityTarget) -> [IdentityComparisonRow] {
        [
            IdentityComparisonRow(field: "设备型号", realValue: real.marketingName, targetValue: target.marketingName),
            IdentityComparisonRow(field: "ProductType", realValue: real.productType, targetValue: target.productType),
            IdentityComparisonRow(field: "架构", realValue: real.architecture, targetValue: target.architecture),
            IdentityComparisonRow(field: "iOS 版本", realValue: real.systemVersion, targetValue: target.systemVersion),
            IdentityComparisonRow(field: "Build", realValue: real.buildNumber, targetValue: target.buildNumber),
            IdentityComparisonRow(field: "逻辑宽", realValue: "\(real.logicalWidth)", targetValue: "\(target.logicalWidth)"),
            IdentityComparisonRow(field: "逻辑高", realValue: "\(real.logicalHeight)", targetValue: "\(target.logicalHeight)"),
            IdentityComparisonRow(field: "原生宽", realValue: "\(real.nativeWidth)", targetValue: "\(target.nativeWidth)"),
            IdentityComparisonRow(field: "原生高", realValue: "\(real.nativeHeight)", targetValue: "\(target.nativeHeight)"),
            IdentityComparisonRow(field: "Scale", realValue: "\(real.scale)", targetValue: "\(target.scale)")
        ]
    }
}
