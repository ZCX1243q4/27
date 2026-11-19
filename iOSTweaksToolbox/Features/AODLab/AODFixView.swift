//
//  AODFixView.swift
//  iOSTweaksToolbox
//
//  AOD 息屏后双击不亮屏：原因分析 + 可执行的修复动作。
//

import SwiftUI

/// AOD 与双击唤醒相关的 MobileGestalt 键。
enum AODKeys {
    static let aod = "2OOJf1VhaM7NxfRok3HbWQ"        // DeviceSupportsAlwaysOnDisplay
    static let aodTime = "j8/Omm6s1lsmTDFsXjsBfA"    // DeviceSupportsAlwaysOnTime
    static let aodVibrancy = "ykpu7qyhqFweVMKtxNylWA" // DeviceSupportsAODVibrancy
    static let tapToWake = "yZf3GTRMGTuwSV/lD7Cagw"  // DeviceSupportsTapToWake

    static let all = [aod, aodTime, aodVibrancy, tapToWake]

    static func name(_ key: String) -> String {
        switch key {
        case aod: return "全天候显示 AOD"
        case aodTime: return "AOD 时间显示"
        case aodVibrancy: return "AOD 鲜艳度"
        case tapToWake: return "轻点唤醒 TapToWake"
        default: return key
        }
    }
}

struct AODFixView: View {
    @EnvironmentObject private var app: AppState

    @State private var values: [String: Any] = [:]
    @State private var status = "未读取"
    @State private var busy = false
    @State private var log: [String] = []

    var body: some View {
        List {
            Section {
                ForEach(AODKeys.all, id: \.self) { key in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AODKeys.name(key)).font(.footnote)
                            Text(key)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(display(values[key]))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(values[key] == nil ? .tertiary : .primary)
                    }
                }
                KeyValueRow(key: "状态", value: status)
            } header: {
                Text("当前 MobileGestalt 值")
            } footer: {
                Text("读取需要 worse_query 令牌。拿不到令牌时会显示「不可读」，不会用推测值填充。")
            }

            Section {
                Button {
                    refresh()
                } label: {
                    Label("读取当前值", systemImage: "arrow.down.doc")
                }

                Button {
                    applyFix()
                } label: {
                    Label("执行修复：轻点唤醒置 1，清除 AOD 鲜艳度", systemImage: "wrench.adjustable")
                }
                .disabled(busy || values.isEmpty)

                Button {
                    applyMinimal()
                } label: {
                    Label("保守修复：只置轻点唤醒 = 1", systemImage: "1.circle")
                }
                .disabled(busy || values.isEmpty)

                Button {
                    rollback()
                } label: {
                    Label("还原到修改前（PreApply 快照）", systemImage: "arrow.uturn.backward")
                }
                .disabled(busy)
            } header: {
                Text("修复动作")
            } footer: {
                Text("写入协议：快照 → 原位覆盖（pwrite，不先清空）→ F_FULLFSYNC → 读回校验 → 失败自动回滚。修改后需要重启设备才生效。")
            }

            Section {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("为什么会出现这个问题")
            }

            if !log.isEmpty {
                Section("操作记录") {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("AOD 双击唤醒修复")
        .onAppear { refresh() }
    }

    private var explanation: String {
        """
        这份缓存（com.apple.MobileGestalt.plist 的 CacheExtra）是 iOS 用来回答「这台设备支持什么」的唯一数据源。你之前强开 AOD 时，它被改成了支持 AOD —— 但 AOD 是「显示屏常亮低功耗模式」，而 iPhone 16e 本身没有 AOD 硬件管线，系统进入 AOD 状态后，锁屏的空闲计时器仍按「屏幕已常亮」判断，于是息屏后的轻点/双击唤醒路径就不会被触发。

        更具体地说，问题通常出在两处之一：
        1. DeviceSupportsTapToWake（yZf3GTRMGTuwSV/lD7Cagw）被连带写成了 0 或缺失，系统认为这台机器不支持轻点唤醒；
        2. AOD 相关键（AOD / AODTime / AODVibrancy）与硬件不匹配，系统进入了无法被触摸唤醒的显示状态。

        所以修复不是「关掉 AOD」这么粗暴：先把轻点唤醒强制置 1，再清掉多余的 AOD 鲜艳度键（真机 AOD 机型有专门的显示管线支持它，强开的机器没有），保留基础 AOD 键。执行后重启设备验证。
        """
    }

    private func display(_ value: Any?) -> String {
        guard let value else { return "不存在" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        return PlistService.preview(of: value, limit: 40)
    }

    private func ensureAccess() -> Bool {
        if WorseQuery.shared.hasGroup, GestaltService.readSystem() != nil { return true }
        let result = WorseQuery.shared.grant(MGPath.systemGestalt)
        append(result.message)
        return result.ok
    }

    private func refresh() {
        guard ensureAccess(), let snapshot = GestaltService.readSystem(),
              let dict = GestaltService.parse(snapshot.data),
              let extra = dict["CacheExtra"] as? [String: Any] else {
            status = "不可读（需要 worse_query 令牌与 App Group 权限）"
            values = [:]
            return
        }
        var result: [String: Any] = [:]
        for key in AODKeys.all where extra[key] != nil { result[key] = extra[key] }
        values = result
        status = "已读取 \(result.count) 个相关键"
    }

    /// 完整修复：轻点唤醒置 1，移除 AOD 鲜艳度。
    private func applyFix() {
        busy = true
        defer { busy = false }
        guard ensureAccess() else { return }
        // 鲜艳度需要真实 AOD 显示管线，强开的机器保留它反而会锁死显示状态，这里清掉
        let removals = values[AODKeys.aodVibrancy] != nil ? [AODKeys.aodVibrancy] : []
        do {
            let before = try GestaltService.applyCacheExtra([AODKeys.tapToWake: 1],
                                                            removing: removals,
                                                            workspace: app.workspace,
                                                            note: "AOD 双击唤醒修复")
            savePreApply(before)
            append("已写入：TapToWake = 1" + (removals.isEmpty ? "" : "，并移除 AODVibrancy"))
            append("请注销或重启后验证息屏双击")
            refresh()
            confirmRespring()
        } catch {
            append("写入失败：\(error.localizedDescription)")
        }
    }

    /// 保守修复：只动轻点唤醒。
    private func applyMinimal() {
        busy = true
        defer { busy = false }
        guard ensureAccess() else { return }
        do {
            let before = try GestaltService.applyCacheExtra([AODKeys.tapToWake: 1],
                                                            workspace: app.workspace,
                                                            note: "仅置 TapToWake")
            savePreApply(before)
            append("已写入：TapToWake = 1（未改动 AOD 键）")
            refresh()
            confirmRespring()
        } catch {
            append("写入失败：\(error.localizedDescription)")
        }
    }

    private func savePreApply(_ data: Data) {
        let url = GestaltService.fileURL(app.workspace, MGPath.preApply)
        try? data.write(to: url, options: .atomic)
    }

    private func rollback() {
        busy = true
        defer { busy = false }
        guard ensureAccess() else { return }
        let url = GestaltService.fileURL(app.workspace, MGPath.preApply)
        guard let data = try? Data(contentsOf: url) else {
            append("没有找到 PreApply 快照")
            return
        }
        do {
            try GestaltService.writeInPlace(data, to: URL(fileURLWithPath: MGPath.systemGestalt))
            append("已还原到修改前状态，请重启设备")
            refresh()
        } catch {
            append("还原失败：\(error.localizedDescription)")
        }
    }

    private func confirmRespring() {
        Support.confirm(title: "需要注销才生效",
                        message: "轻点唤醒与 AOD 的判定在 SpringBoard 启动时读取。是否现在注销？",
                        destructive: "立即注销") {
            app.respring("AOD 双击唤醒修复")
        }
    }

    private func append(_ line: String) {
        log.insert(line, at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
        app.log.info("[AODFix] \(line)")
    }
}
