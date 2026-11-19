//
//  FileBrowserView.swift
//  iOSTweaksToolbox
//
//  沙盒、App Group 与用户授权目录的文件浏览。
//

import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @EnvironmentObject private var app: AppState
    @State private var current: URL?
    @State private var items: [FileMeta] = []
    @State private var errorText: String?
    @State private var showImporter = false
    @State private var previewURL: URL?

    var body: some View {
        List {
            Section("位置") {
                Button("App 沙盒 Documents") { open(app.workspace.documents) }
                Button("工具箱工作区") { open(app.workspace.root) }
                Button("备份目录") { open(app.workspace.backups) }
                if let group = WorkspacePaths.appGroupURL() {
                    Button("App Group 容器") { open(group) }
                } else {
                    HStack {
                        Text("App Group 容器").foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(text: "无 entitlement", tint: .red)
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    Label("选择外部文件夹", systemImage: "folder.badge.plus")
                }
            }

            if let current {
                Section(header: Text(current.path).font(.caption2)) {
                    if items.isEmpty {
                        EmptyStateView(symbol: "folder", title: "空目录",
                                       message: "该目录没有可读取的条目，或权限不足")
                    }
                    ForEach(items) { meta in
                        row(meta)
                    }
                }
            }

            if let errorText {
                Section { Text(errorText).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("文件管理器")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    open(url)
                    if scoped { app.log.append(.info, "已获得授权目录访问：\(url.path)") }
                }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private func row(_ meta: FileMeta) -> some View {
        HStack(spacing: 10) {
            Image(systemName: meta.isDirectory ? "folder.fill" : "doc.text")
                .foregroundStyle(meta.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.name).font(.footnote)
                Text("\(meta.kind.rawValue) · \(ByteCountFormatter.string(fromByteCount: meta.size, countStyle: .file))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if meta.isDirectory {
                    Button("打开") { open(meta.url) }
                } else {
                    Button("预览") { previewURL = meta.url }
                    Button("Hex 查看") { previewURL = meta.url }
                }
                Button("复制 SHA-256") {
                    UIPasteboard.general.string = Hashing.sha256(of: meta.url) ?? ""
                }
                Button("删除", role: .destructive) { delete(meta) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if meta.isDirectory { open(meta.url) } else { previewURL = meta.url }
        }
    }

    private func open(_ url: URL) {
        current = url
        errorText = nil
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url,
                                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])
            items = urls.map { FileInspector.meta(for: $0) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        } catch {
            items = []
            errorText = "无法列出：\(error.localizedDescription)"
            app.log.append(.warning, "列目录失败：\(url.lastPathComponent) — \(error.localizedDescription)")
        }
    }

    private func delete(_ meta: FileMeta) {
        do {
            try FileManager.default.removeItem(at: meta.url)
            app.log.append(.success, "已删除：\(meta.path)")
            if let current { open(current) }
        } catch {
            errorText = error.localizedDescription
            app.log.append(.error, "删除失败：\(error.localizedDescription)")
        }
    }
}
