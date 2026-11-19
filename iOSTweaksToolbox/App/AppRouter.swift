//
//  AppRouter.swift
//  iOSTweaksToolbox
//
//  模块注册表与全局 AppState。
//

import Foundation
import SwiftUI
import Combine

// MARK: - 模块

enum AppModule: String, CaseIterable, Identifiable, Hashable {
    case configurationEditor
    case profileManager
    case jsonEditor
    case hexEditor
    case dynamicIsland
    case displayLab
    case aodLab
    case deviceIdentity
    case fileManager
    case backup
    case deviceInfo
    case diagnostics
    case capabilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configurationEditor: return "配置编辑器"
        case .profileManager: return "配置方案中心"
        case .jsonEditor: return "JSON 编辑器"
        case .hexEditor: return "Hex 编辑器"
        case .dynamicIsland: return "灵动岛工作室"
        case .displayLab: return "显示分辨率实验室"
        case .aodLab: return "AOD 实验室"
        case .deviceIdentity: return "设备身份管理"
        case .fileManager: return "文件管理器"
        case .backup: return "备份与恢复"
        case .deviceInfo: return "设备信息"
        case .diagnostics: return "诊断与日志"
        case .capabilities: return "能力矩阵"
        }
    }

    var subtitle: String {
        switch self {
        case .configurationEditor: return "Plist / XML / Binary 真实解析、编辑与保存"
        case .profileManager: return "方案库、导入导出、版本与恢复"
        case .jsonEditor: return "格式化、校验、键值搜索与替换"
        case .hexEditor: return "字节级查看与就地修改"
        case .dynamicIsland: return "位置、尺寸、圆角与展开状态模拟"
        case .displayLab: return "读取真实屏幕参数，建立自定义显示方案"
        case .aodLab: return "AOD 开关前后行为记录与配置差异诊断"
        case .deviceIdentity: return "按 App 记录目标设备身份（研究用配置）"
        case .fileManager: return "沙盒、App Group 与用户授权目录"
        case .backup: return "SHA-256 校验、快照与恢复"
        case .deviceInfo: return "硬件、系统、内存与电池"
        case .diagnostics: return "事件时间线、权限探测、报告导出"
        case .capabilities: return "每个功能的真实可用性状态"
        }
    }

    var systemImage: String {
        switch self {
        case .configurationEditor: return "doc.text.magnifyingglass"
        case .profileManager: return "square.stack.3d.up"
        case .jsonEditor: return "curlybraces"
        case .hexEditor: return "number"
        case .dynamicIsland: return "capsule.portrait"
        case .displayLab: return "rectangle.on.rectangle"
        case .aodLab: return "moon.stars"
        case .deviceIdentity: return "person.badge.key"
        case .fileManager: return "folder"
        case .backup: return "arrow.triangle.2.circlepath"
        case .deviceInfo: return "iphone.gen3"
        case .diagnostics: return "stethoscope"
        case .capabilities: return "checklist"
        }
    }

    var priority: ModulePriority {
        switch self {
        case .configurationEditor, .profileManager, .jsonEditor, .hexEditor,
             .dynamicIsland, .displayLab, .aodLab, .deviceIdentity:
            return .p0
        case .fileManager, .backup, .deviceInfo:
            return .p1
        case .diagnostics, .capabilities:
            return .p2
        }
    }
}

enum ModulePriority: String {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"

    var tint: Color {
        switch self {
        case .p0: return .red
        case .p1: return .orange
        case .p2: return .blue
        }
    }
}

// MARK: - 全局状态

@MainActor
final class AppState: ObservableObject {
    let workspace: WorkspacePaths
    let log: EventLog
    let backups: BackupService
    let profileStore: ProfileStore
    let identityStore: IdentityStore
    let aod: AODLabService
    let capabilities: CapabilityRegistry
    let deviceInfo: DeviceInfoService

    @Published var bootstrapped = false
    @Published var path: [AppModule] = []

    init() {
        let workspace = WorkspacePaths()
        self.workspace = workspace
        self.log = EventLog()
        self.backups = BackupService(workspace: workspace, log: nil)
        self.profileStore = ProfileStore(workspace: workspace)
        self.identityStore = IdentityStore(workspace: workspace)
        self.aod = AODLabService(workspace: workspace)
        self.capabilities = CapabilityRegistry(workspace: workspace)
        self.deviceInfo = DeviceInfoService()
        self.backups.attachLog(log)
        AppLogger.shared.sink = log
        forwardChanges()
    }

    private var cancellables = Set<AnyCancellable>()

    /// 让各服务的变化都能触发环境对象刷新。
    private func forwardChanges() {
        let publishers: [ObservableObjectPublisher] = [
            log.objectWillChange,
            backups.objectWillChange,
            profileStore.objectWillChange,
            identityStore.objectWillChange,
            aod.objectWillChange,
            capabilities.objectWillChange
        ]
        for publisher in publishers {
            publisher.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        }
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        workspace.prepare()
        profileStore.seedIfEmpty()
        identityStore.load()
        aod.load()
        await capabilities.refresh()
        log.append(.info, "工作区就绪：\(workspace.root.path)")
        bootstrapped = true
    }
}
