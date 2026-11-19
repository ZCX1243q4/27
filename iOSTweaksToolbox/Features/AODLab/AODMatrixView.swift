//
//  AODMatrixView.swift
//  iOSTweaksToolbox
//
//  AOD 键组逐项开关。用来定位到底是哪个键破坏了息屏双击——
//  因为真机上「AOD 一开就双击无效」是显示状态问题，不是 TapToWake 值问题，
//  只能靠逐键排除法找到最小组。
//

import SwiftUI

struct AODMatrixView: View {
    @EnvironmentObject private var app: AppState

    @State private var current: [String: Any] = [:]
    @State private var busy = false
    @State private var output: [String] = []
    @State private var combination: Combination = .aodOnly

    enum Combination: String, CaseIterable, Identifiable {
        case aodOnly = "只写 AOD"
        case aodPlusTime = "AOD + AOTime"
        case allThree = "AOD + AOTime + 鲜艳度"
        case baseline = "全部清除（对照）"

        var id: String { rawValue }

        var keys: [String] {
            switch self {
            case .aodOnly: return [AODKeys.aod]
            case .aodPlusTime: return [AODKeys.aod, AODKeys.aodTime]
            case .allThree: return [AODKeys.aod, AODKeys.aodTime, AODKeys.aodVibrancy]
            case .baseline: return []
            }
        }

        var detail: String {
            switch self {
            case .aodOnly: return "只开常亮显示，不写时间与鲜艳度"
            case .aodPlusTime: return "Erosion 官方开关实际写入的组合"
            case .allThree: return "再加鲜艳度，最接近原生 AOD 机型"
            case .baseline: return "三个键全部移除，回到未强开状态"
            }
        }
    }

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "AOD", value: describe(current[AODKeys.aod]))
                KeyValueRow(key: "AOTime", value: describe(current[AODKeys.aodTime]))
                KeyValueRow(key: "AODVibrancy", value: describe(current[AODKeys.aodVibrancy]))
                KeyValueRow(key: "TapToWake", value: describe(current[AODKeys.tapToWake]))
            } header: {
                Text("系统当前值")
            } footer: {
                Text("TapToWake 在 iPhone 16e 上出厂就是 1。如果它是 1 而双击仍失效，说明问题不在这个键。")
            }

            Section {
                Picker("写入组合", selection: $combination) {
                    ForEach(Combination.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(combination.detail).font(.caption).foregroundStyle(.secondary)
                ForEach(combination.keys, id: \.self) { key in
                    Text("→ \(AODKeys.name(key))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.green)
                }
                Button {
                    apply()
                } label: {
                    Label("写入这个组合", systemImage: "square.and.arrow.down")
                }
                .disabled(busy)
            } header: {
                Text("逐项排除")
            } footer: {
                Text("每写一次 → 注销或重启 → 锁屏息屏后双击测试 → 回来记结果。四个组合试完就能确定是哪个键导致的。")
            }

            Section {
                Button {
                    app.respring("AOD 组合测试")
                } label: {
                    Label("尝试注销", systemImage: "arrow.clockwise.circle")
                }
                if !output.isEmpty {
                    ForEach(Array(output.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("""
                为什么这样做：

                真机上「AOD 开启 → 息屏双击不亮，AOD 关闭 → 立刻恢复」这个现象，改 TapToWake 是没用的——你的机器出厂就支持轻点唤醒，那个键一直是 1。

                真正的机制是：AOD 让锁屏进入常亮显示状态后，显示屏驱动与触摸唤醒的交接由 SpringBoard 的显示状态机负责。强开的 AOD 在 16e 上缺一套硬件描述（这台机器没有 AOD 专用显示管线），状态机停在「已常亮」就不会响应唤醒触摸。

                所以只能做排除法：把 AOD 的三个键拆开逐个写入，看哪一个是破坏点。如果「只写 AOD」就已经坏，「AOD + AOTime」反而正常，那就说明 AOTime 是必须的；如果三个都写还是坏，那就是硬件层面的限制，任何 MobileGestalt 组合都救不回来——那时候唯一能做的选择就是「要么 AOD，要么双击唤醒」。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AOD 键组排除")
        .onAppear { refresh() }
    }

    private func describe(_ value: Any?) -> String {
        guard let value else { return "不存在" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        return String(describing: value)
    }

    private func refresh() {
        _ = WorseQuery.shared.grant(MGPath.systemGestalt)
        current = GestaltService.readCacheExtra([AODKeys.aod,
                                                 AODKeys.aodTime,
                                                 AODKeys.aodVibrancy,
                                                 AODKeys.tapToWake])
    }

    private func apply() {
        busy = true
        defer { busy = false }
        do {
            var edits: [String: Any] = [:]
            for key in combination.keys { edits[key] = 1 }
            var removals: [String] = []
            if combination == .baseline {
                removals = [AODKeys.aod, AODKeys.aodTime, AODKeys.aodVibrancy]
            }
            _ = try GestaltService.applyCacheExtra(edits,
                                                    removing: removals,
                                                    workspace: app.workspace,
                                                    note: "AOD 组合：\(combination.rawValue)")
            output.insert("已写入：\(combination.rawValue)", at: 0)
            app.log.ok("AOD 组合已写入：\(combination.rawValue)")
            refresh()
        } catch {
            output.insert("写入失败：\(error.localizedDescription)", at: 0)
            app.log.fail("AOD 组合写入失败：\(error.localizedDescription)")
        }
    }
}
