//
//  DashboardView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState

    private var modules: [AppModule] { AppModule.allCases }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            ForEach([ModulePriority.p0, .p1, .p2], id: \.self) { priority in
                Section {
                    ForEach(modules.filter { $0.priority == priority }) { module in
                        NavigationLink(value: module) {
                            row(module)
                        }
                    }
                } header: {
                    HStack {
                        Text(priority.rawValue + " 模块")
                        Spacer()
                        Text("\(modules.filter { $0.priority == priority }.count)")
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                Text("本工具在未越狱环境运行。所有涉及系统级改动的功能，只会写入你自己拥有权限的文件；无法访问的路径显示真实权限状态，不伪造成功，也不把模拟效果当成系统修改。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("玩机工具箱")
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DeviceInfoService.marketingName(for: DeviceInfoService.hardwareIdentifier()))
                        .font(.headline)
                    Text("iOS \(DeviceInfoService.report().systemVersion) · \(DeviceInfoService.buildNumber())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                StatTile(title: "P0", value: "8", caption: "首版必做")
                StatTile(title: "方案", value: "\(app.profileStore.profiles.count)", caption: "本地方案库")
                StatTile(title: "快照", value: "\(app.backups.records.count)", caption: "修改前备份")
            }
        }
    }

    private func row(_ module: AppModule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.systemImage)
                .frame(width: 26)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.body)
                Text(module.subtitle).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            StatusBadge(text: module.priority.rawValue, tint: module.priority.tint)
        }
        .padding(.vertical, 2)
    }
}
