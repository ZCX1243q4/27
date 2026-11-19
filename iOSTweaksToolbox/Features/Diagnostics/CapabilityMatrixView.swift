//
//  CapabilityMatrixView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct CapabilityMatrixView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section {
                ForEach(app.capabilities.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name).font(.subheadline.weight(.medium))
                            Spacer()
                            CapabilityBanner(status: item.status)
                        }
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("运行时探测结果")
            } footer: {
                if let date = app.capabilities.lastRefresh {
                    Text("最近探测：\(date.formatted(date: .abbreviated, time: .standard))")
                }
            }

            Section {
                NavigationLink {
                    SelfCheckView()
                } label: {
                    Label("真机自检（逐项显示返回码）", systemImage: "stethoscope")
                }
            }

            Section("版本窗口") {
                KeyValueRow(key: "当前系统", value: "iOS \(OSCompatibility.systemVersion) (\(OSCompatibility.build))")
                KeyValueRow(key: "机型标识", value: OSCompatibility.model)
                KeyValueRow(key: "是否目标机型 iPhone 16e", value: OSCompatibility.isTargetDevice ? "是" : "否")
                KeyValueRow(key: "已知越界技术窗口", value: OSCompatibility.sandboxEscapeWindow)
                KeyValueRow(key: "当前构建是否已修复", value: OSCompatibility.isPatchedBuild ? "是" : "否")
            }
        }
        .navigationTitle("能力矩阵")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.capabilities.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}
