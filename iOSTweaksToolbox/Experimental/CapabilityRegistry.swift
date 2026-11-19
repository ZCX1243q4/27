//
//  CapabilityRegistry.swift
//  iOSTweaksToolbox
//
//  运行时真实探测每一项能力的可用性。探测结果会写进日志与能力矩阵页。
//

import Foundation
import SwiftUI

@MainActor
final class CapabilityRegistry: ObservableObject {
    @Published private(set) var items: [Capability] = []
    @Published private(set) var lastRefresh: Date?

    private let workspace: WorkspacePaths
    private let fm = FileManager.default

    init(workspace: WorkspacePaths) {
        self.workspace = workspace
    }

    func refresh() async {
        var result: [Capability] = []

        // 1. App 自身沙盒
        let documents = workspace.documents
        result.append(Capability(name: "App 自身沙盒读写",
                                 status: fm.isWritableFile(atPath: documents.path) ? .available : .unavailable,
                                 detail: documents.path))

        // 2. App Group
        if let group = WorkspacePaths.appGroupURL() {
            result.append(Capability(name: "App Group 容器",
                                     status: fm.isWritableFile(atPath: group.path) ? .available : .conditional,
                                     detail: group.path))
        } else {
            result.append(Capability(name: "App Group 容器",
                                     status: .unavailable,
                                     detail: "签名的 entitlements 未包含 com.apple.security.application-groups"))
        }

        // 3. 用户授权目录
        result.append(Capability(name: "用户授权目录",
                                 status: .available,
                                 detail: "通过「文件」选择器获得的安全作用域 URL"))

        // 4. 系统容器（未越狱）
        let systemProbe = "/private/var/mobile/Containers/Data/Application"
        let reachable = (try? fm.contentsOfDirectory(atPath: systemProbe)) != nil
        result.append(Capability(name: "其他 App 容器目录",
                                 status: reachable ? .conditional : .unavailable,
                                 detail: reachable
                                    ? "当前进程能列出该目录（可能已具备额外授权）"
                                    : "未越狱普通 App 被沙盒拒绝，仅显示权限状态"))

        // 5. 系统文件写入
        let systemWriteProbe = "/private/var/preferences"
        result.append(Capability(name: "系统配置文件写入",
                                 status: fm.isWritableFile(atPath: systemWriteProbe) ? .conditional : .unavailable,
                                 detail: "普通侧载 App 不具备该权限；工具不会伪造成功"))

        // 6. SpringBoard 灵动岛
        result.append(Capability(name: "SpringBoard 灵动岛位置修改",
                                 status: .research,
                                 detail: "无公开 API；本工具只提供 App 内模拟器"))

        // 7. 全局逻辑分辨率
        result.append(Capability(name: "全局逻辑分辨率修改",
                                 status: .research,
                                 detail: "需要系统显示服务授权；本工具只提供方案模拟"))

        // 8. AOD 底层行为
        result.append(Capability(name: "AOD 底层行为修改",
                                 status: .research,
                                 detail: "无法修改锁屏服务；本工具做行为记录与配置差异分析"))

        // 9. 逐 App 设备型号伪装
        result.append(Capability(name: "逐 App 设备型号伪装",
                                 status: .research,
                                 detail: "未越狱环境没有公开接口可拦截他人 API 调用"))

        // 10. 版本窗口
        result.append(Capability(name: "沙盒越界技术窗口",
                                 status: OSCompatibility.isPatchedBuild ? .unavailable : .conditional,
                                 detail: OSCompatibility.sandboxEscapeWindow))

        items = result
        lastRefresh = Date()
    }

    func text() -> String {
        items.map { "\($0.name) [\($0.status.rawValue)] — \($0.detail)" }.joined(separator: "\n")
    }
}
