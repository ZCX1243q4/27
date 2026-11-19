//
//  DeviceInfoView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct DeviceInfoView: View {
    @EnvironmentObject private var app: AppState
    @State private var report: DeviceInfoReport?

    var body: some View {
        List {
            if let report {
                Section("设备") {
                    KeyValueRow(key: "市场名称", value: report.marketingName)
                    KeyValueRow(key: "硬件标识", value: report.hardwareIdentifier, mono: true)
                    KeyValueRow(key: "架构", value: report.architecture, mono: true)
                    KeyValueRow(key: "系统", value: "\(report.systemName) \(report.systemVersion) (\(report.buildNumber))")
                    KeyValueRow(key: "处理器核心", value: "\(report.processorCount)")
                }
                Section("内存与存储") {
                    KeyValueRow(key: "物理内存", value: Self.bytes(report.physicalMemory))
                    KeyValueRow(key: "磁盘总容量", value: Self.bytes(report.diskTotal))
                    KeyValueRow(key: "可用空间", value: Self.bytes(report.diskFree))
                }
                Section("电池与温控") {
                    KeyValueRow(key: "电量", value: report.batteryLevel < 0 ? "未知" : String(format: "%.0f%%", report.batteryLevel * 100))
                    KeyValueRow(key: "充电状态", value: report.batteryState)
                    KeyValueRow(key: "温控状态", value: report.thermalState)
                    KeyValueRow(key: "低电量模式", value: report.lowPowerMode ? "开启" : "关闭")
                }
                Section("标识") {
                    KeyValueRow(key: "IDFV", value: report.identifierForVendor, mono: true)
                    Text("本工具不读取、也不展示设备唯一硬件标识（如序列号、UDID）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                EmptyStateView(symbol: "iphone.gen3", title: "正在读取", message: "设备信息读取中")
            }
        }
        .navigationTitle("设备信息")
        .task { report = DeviceInfoService.report() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportReport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(report == nil)
            }
        }
    }

    private func exportReport() {
        guard let report else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        let url = app.workspace.journals.appendingPathComponent("device-report.json")
        try? data.write(to: url, options: .atomic)
        app.log.append(.success, "设备报告已导出：\(url.path)")
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
