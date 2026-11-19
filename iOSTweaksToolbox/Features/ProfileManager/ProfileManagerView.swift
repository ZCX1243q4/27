//
//  ProfileManagerView.swift
//  iOSTweaksToolbox
//

import SwiftUI
import UniformTypeIdentifiers

struct ProfileManagerView: View {
    @EnvironmentObject private var app: AppState
    @State private var category: ProfileCategory = .dynamicIsland
    @State private var showImporter = false
    @State private var selected: ProfileDocument?
    @State private var diffPair: [ProfileDocument] = []
    @State private var diffItems: [DiffItem] = []

    var body: some View {
        List {
            Section {
                Picker("分类", selection: $category) {
                    ForEach(ProfileCategory.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("方案") {
                let list = app.profileStore.profiles(in: category)
                if list.isEmpty {
                    EmptyStateView(symbol: "square.stack.3d.up", title: "没有方案",
                                   message: "导入 JSON 或用编辑器保存一份")
                } else {
                    ForEach(list) { profile in
                        Button {
                            selected = profile
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(.footnote)
                                Text(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(profile.payload.prefix(80))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? app.profileStore.delete(list[index])
                        }
                    }
                }
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("导入方案 JSON", systemImage: "square.and.arrow.down")
                }
                if app.profileStore.profiles(in: category).count >= 2 {
                    Button {
                        let list = app.profileStore.profiles(in: category)
                        diffPair = Array(list.prefix(2))
                        compare()
                    } label: {
                        Label("对比最近两份方案", systemImage: "arrow.left.arrow.right")
                    }
                }
            }

            if !diffItems.isEmpty {
                Section("差异（\(diffItems.count) 处）") {
                    ForEach(diffItems.prefix(60)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.path).font(.system(.caption2, design: .monospaced))
                            Text("\(item.oldValue) → \(item.newValue)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("方案库位于 \(app.workspace.profiles.path)。这是本工具自己的 JSON 格式，与 iOS 系统配置路径无关。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("配置方案中心")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    _ = try app.profileStore.importProfile(from: url, category: category)
                    app.log.append(.success, "已导入方案：\(url.lastPathComponent)")
                } catch {
                    app.log.append(.error, "导入失败：\(error.localizedDescription)")
                }
            }
        }
        .sheet(item: $selected) { profile in
            NavigationStack {
                ScrollView {
                    Text(profile.payload)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(profile.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { selected = nil }
                    }
                }
            }
        }
    }

    private func compare() {
        guard diffPair.count == 2 else { return }
        guard let a = try? PlistService.load(data: Data(diffPair[0].payload.utf8)).root,
              let b = try? PlistService.load(data: Data(diffPair[1].payload.utf8)).root else {
            diffItems = []
            return
        }
        diffItems = DiffEngine.diff(old: a, new: b)
    }
}
