//
//  DisplayLabView.swift
//  iOSTweaksToolbox
//
//  真实屏幕参数 + 自定义显示方案（模拟值）。
//

import SwiftUI

struct DisplayLabView: View {
    @EnvironmentObject private var app: AppState

    @State private var snapshot: DisplaySnapshot?
    @State private var profileName = "Custom Display Profile"
    @State private var logicalWidth: Double = 390
    @State private var logicalHeight: Double = 844
    @State private var simScale: Double = 3

    private var simulation: DisplayProfile {
        DisplayProfile(name: profileName,
                       logicalWidth: logicalWidth,
                       logicalHeight: logicalHeight,
                       scale: simScale)
    }

    var body: some View {
        List {
            if let snapshot {
                Section("真实显示参数") {
                    HStack(spacing: 8) {
                        StatTile(title: "逻辑尺寸",
                                 value: "\(Int(snapshot.boundsWidth))×\(Int(snapshot.boundsHeight))")
                        StatTile(title: "原生像素",
                                 value: "\(Int(snapshot.nativeBoundsWidth))×\(Int(snapshot.nativeBoundsHeight))")
                        StatTile(title: "Scale", value: String(format: "%.1f", snapshot.scale))
                    }
                    KeyValueRow(key: "Native Scale", value: String(format: "%.3f", snapshot.nativeScale))
                    KeyValueRow(key: "设备标识", value: snapshot.deviceModel, mono: true)
                    KeyValueRow(key: "系统", value: "\(snapshot.systemVersion) (\(snapshot.buildNumber))")
                    KeyValueRow(key: "安全区", value: "顶部 \(Int(snapshot.safeAreaTop)) pt / 底部 \(Int(snapshot.safeAreaBottom)) pt")
                }
            }

            Section {
                slider("逻辑宽度", value: $logicalWidth, range: 320...460)
                slider("逻辑高度", value: $logicalHeight, range: 660...1000)
                slider("Scale", value: $simScale, range: 2...4)
                DisplayShapePreview(profile: simulation, island: IslandConfiguration.original)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("自定义显示方案（模拟）")
            } footer: {
                Text("这些数值只用于 App 内的布局推演。iOS 的全局显示模式由系统显示服务管理，普通 App 写入一个 JSON 不会改变系统分辨率。")
            }

            Section("保存与载入") {
                HStack {
                    TextField("方案名称", text: $profileName)
                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }

            Section("方案库") {
                let list = app.profileStore.profiles(in: .display)
                if list.isEmpty {
                    EmptyStateView(symbol: "rectangle.on.rectangle", title: "没有方案",
                                   message: "调整参数后保存一份")
                } else {
                    ForEach(list) { document in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.name).font(.footnote)
                                Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("载入") { load(document) }.font(.caption)
                        }
                    }
                }
            }

            Section {
                Button {
                    exportReport()
                } label: {
                    Label("导出显示参数报告", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("报告包含真实读取值与模拟方案的完整对照，模拟段落会明确标注。")
            }
        }
        .navigationTitle("显示分辨率实验室")
        .onAppear {
            let snap = DisplayService.snapshot()
            snapshot = snap
            logicalWidth = snap.boundsWidth
            logicalHeight = snap.boundsHeight
            simScale = snap.scale
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.footnote)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func save() {
        var toSave = simulation
        toSave.name = profileName.isEmpty ? "Custom" : profileName
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(toSave),
              let text = String(data: data, encoding: .utf8) else { return }
        let document = ProfileDocument(name: toSave.name.replacingOccurrences(of: " ", with: "-"),
                                       category: .display,
                                       createdAt: Date(),
                                       updatedAt: Date(),
                                       payload: text,
                                       note: "显示方案（模拟）")
        do {
            try app.profileStore.save(document)
            app.log.append(.success, "已保存显示方案：\(toSave.name)")
        } catch {
            app.log.append(.error, "保存失败：\(error.localizedDescription)")
        }
    }

    private func load(_ document: ProfileDocument) {
        guard let data = document.payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DisplayProfile.self, from: data) else {
            app.log.append(.error, "方案解析失败：\(document.name)")
            return
        }
        profileName = decoded.name
        logicalWidth = decoded.logicalWidth
        logicalHeight = decoded.logicalHeight
        simScale = decoded.scale
        app.log.append(.info, "已载入显示方案：\(decoded.name)")
    }

    private func exportReport() {
        guard let snapshot else { return }
        let payload: [String: Any] = [
            "real": ["logicalWidth": snapshot.boundsWidth,
                     "logicalHeight": snapshot.boundsHeight,
                     "nativeWidth": snapshot.nativeBoundsWidth,
                     "nativeHeight": snapshot.nativeBoundsHeight,
                     "scale": snapshot.scale,
                     "nativeScale": snapshot.nativeScale],
            "simulation": ["name": profileName,
                           "logicalWidth": logicalWidth,
                           "logicalHeight": logicalHeight,
                           "scale": simScale,
                           "isSimulation": true],
            "note": "simulation 段是本工具内的模拟参数，不是系统实际值"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = app.workspace.journals.appendingPathComponent("display-report.json")
        do {
            try data.write(to: url, options: .atomic)
            app.log.append(.success, "显示报告已导出：\(url.path)")
        } catch {
            app.log.append(.error, "导出失败：\(error.localizedDescription)")
        }
    }
}

struct DisplayShapePreview: View {
    var profile: DisplayProfile
    var island: IslandConfiguration

    var body: some View {
        GeometryReader { proxy in
            let ratio = profile.logicalHeight > 0 ? profile.logicalWidth / profile.logicalHeight : 0.46
            let height = proxy.size.height
            let width = min(proxy.size.width, height * ratio)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(white: 0.08))
                Capsule()
                    .fill(Color.black)
                    .frame(width: max(60, island.width * (width / max(profile.logicalWidth, 1))),
                           height: max(14, island.height * (height / max(profile.logicalHeight, 1))))
                    .padding(.top, 8)
                VStack(spacing: 4) {
                    Spacer()
                    Text("\(Int(profile.logicalWidth)) × \(Int(profile.logicalHeight)) @\(String(format: "%.2f", profile.scale))x")
                        .font(.caption2).foregroundStyle(.white.opacity(0.85))
                    Text("模拟预览").font(.caption2).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.bottom, 12)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }
}
