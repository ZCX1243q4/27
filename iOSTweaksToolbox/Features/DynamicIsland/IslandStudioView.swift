//
//  IslandStudioView.swift
//  iOSTweaksToolbox
//
//  灵动岛布局研究。所有参数只作用于 App 内模拟器。
//

import SwiftUI

struct IslandStudioView: View {
    @EnvironmentObject private var app: AppState
    @State private var config = IslandConfiguration.original
    @State private var expanded = false
    @State private var profileName = "Custom"

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "屏幕逻辑尺寸", value: "\(Int(DisplayService.snapshot().boundsWidth)) × \(Int(DisplayService.snapshot().boundsHeight))")
                KeyValueRow(key: "原生像素", value: "\(Int(DisplayService.snapshot().nativeBoundsWidth)) × \(Int(DisplayService.snapshot().nativeBoundsHeight))")
                KeyValueRow(key: "安全区顶部", value: "\(Int(DisplayService.snapshot().safeAreaTop)) pt")
                HStack {
                    Text("展开状态").font(.footnote)
                    Spacer()
                    Toggle("", isOn: $expanded).labelsHidden()
                }
            } header: {
                Text("设备基准")
            }

            Section {
                IslandPreviewCanvas(config: config, expanded: expanded)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("模拟器（仅 App 内渲染）")
            } footer: {
                Text("该预览只在本 App 的窗口内绘制。它不会改变 SpringBoard 的真实灵动岛。")
            }

            Section("参数") {
                slider("水平偏移", value: $config.horizontalOffset, range: -40...40, unit: "pt")
                slider("垂直偏移", value: $config.verticalOffset, range: -30...30, unit: "pt")
                slider("宽度", value: $config.width, range: 80...200, unit: "pt")
                slider("高度", value: $config.height, range: 24...60, unit: "pt")
                slider("圆角", value: $config.cornerRadius, range: 8...30, unit: "pt")
                slider("展开宽度", value: $config.expandedWidth, range: 240...420, unit: "pt")
                slider("展开高度", value: $config.expandedHeight, range: 80...200, unit: "pt")
                slider("动画时长", value: $config.animationDuration, range: 0.1...0.8, unit: "s")
            }

            Section("预设") {
                ForEach(IslandConfiguration.presets, id: \.name) { preset in
                    Button {
                        config = preset
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            Text("\(Int(preset.width))×\(Int(preset.height))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                HStack {
                    TextField("方案名称", text: $profileName)
                    Button("保存方案") { save() }
                        .buttonStyle(.borderedProminent)
                }
                ForEach(app.profileStore.profiles(in: .dynamicIsland)) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.footnote)
                            Text(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("载入") { load(profile) }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            } header: {
                Text("方案库")
            }

            Section {
                Text("普通未越狱 App 没有公开接口去移动 SpringBoard 里的灵动岛。这里的参数是可保存、可导出的研究数据；要真正影响系统布局，需要能改到系统级显示配置的权限，本工具不会把预览当成已生效。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("灵动岛工作室")
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.footnote)
                Spacer()
                Text(String(format: "%.2f %@", value.wrappedValue, unit))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func save() {
        var toSave = config
        toSave.name = profileName.isEmpty ? "Custom" : profileName
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(toSave), let text = String(data: data, encoding: .utf8) else { return }
        let profile = ProfileDocument(name: toSave.name.replacingOccurrences(of: " ", with: "-"),
                                      category: .dynamicIsland,
                                      createdAt: Date(), updatedAt: Date(),
                                      payload: text, note: "灵动岛方案")
        try? app.profileStore.save(profile)
        app.log.append(.success, "已保存灵动岛方案：\(toSave.name)")
    }

    private func load(_ profile: ProfileDocument) {
        guard let data = profile.payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(IslandConfiguration.self, from: data) else {
            app.log.append(.error, "方案解析失败：\(profile.name)")
            return
        }
        config = decoded
        profileName = decoded.name
        app.log.append(.info, "已载入方案：\(decoded.name)")
    }
}

struct IslandPreviewCanvas: View {
    var config: IslandConfiguration
    var expanded: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = expanded ? config.expandedWidth : config.width
            let height = expanded ? config.expandedHeight : config.height
            let islandWidth = min(width, proxy.size.width - 24)
            let islandHeight = min(height, proxy.size.height - 40)

            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(white: 0.10), Color(white: 0.03)],
                               startPoint: .top, endPoint: .bottom)

                // 状态栏时间，用来观察灵动岛与顶部的距离
                HStack {
                    Text("9:41").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Image(systemName: "wifi").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: islandWidth, height: islandHeight)
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
                    .overlay(alignment: .center) {
                        if expanded {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("正在播放").font(.caption2.weight(.semibold))
                                    Text("Preview Only").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "forward.fill")
                            }
                            .padding(.horizontal, 16)
                            .foregroundStyle(.white)
                        }
                    }
                    .offset(x: config.horizontalOffset,
                            y: max(10, 12 + config.verticalOffset))
                    .animation(.easeInOut(duration: config.animationDuration), value: expanded)
                    .animation(.easeInOut(duration: config.animationDuration), value: config)

                // 参考线：屏顶到岛顶的距离
                VStack {
                    Rectangle()
                        .fill(Color.green.opacity(0.35))
                        .frame(height: 1)
                        .padding(.top, max(10, 12 + config.verticalOffset))
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }
}
