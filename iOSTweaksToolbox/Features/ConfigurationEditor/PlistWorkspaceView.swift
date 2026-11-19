//
//  PlistWorkspaceView.swift
//  iOSTweaksToolbox
//
//  配置编辑器入口：选择文件 -> Plist / JSON / Hex。
//

import SwiftUI
import UniformTypeIdentifiers

struct PlistWorkspaceView: View {
    @EnvironmentObject private var app: AppState
    @State private var showImporter = false
    @State private var files: [FileMeta] = []
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("导入配置文件", systemImage: "square.and.arrow.down")
                }
                Button {
                    refresh()
                } label: {
                    Label("刷新工作区", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("导入的文件会复制到本 App 的工作区，原文件不会被改动。")
            }

            Section("工作区文件") {
                if files.isEmpty {
                    EmptyStateView(symbol: "doc", title: "还没有文件",
                                   message: "使用上方按钮导入 plist / json / 任意二进制文件")
                } else {
                    ForEach(files) { meta in
                        NavigationLink {
                            destination(for: meta)
                        } label: {
                            fileRow(meta)
                        }
                    }
                }
            }

            if let errorText {
                Section { Text(errorText).font(.footnote).foregroundStyle(.red) }
            }

            Section("系统路径（只读探测）") {
                ForEach(SystemProbe.candidates, id: \.self) { path in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(path).font(.system(.caption2, design: .monospaced))
                            Text(SystemProbe.describe(path)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: FileManager.default.isReadableFile(atPath: path)
                              ? "checkmark.circle" : "lock.slash")
                            .foregroundStyle(FileManager.default.isReadableFile(atPath: path) ? .green : .red)
                    }
                }
            }
        }
        .navigationTitle("配置编辑器")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .onAppear { refresh() }
    }

    @ViewBuilder
    private func destination(for meta: FileMeta) -> some View {
        switch meta.kind {
        case .plistXML, .plistBinary:
            PlistEditorView(url: meta.url)
        case .json, .text:
            JSONEditorWorkspaceView(initialURL: meta.url)
        default:
            HexWorkspaceView(initialURL: meta.url)
        }
    }

    private func fileRow(_ meta: FileMeta) -> some View {
        HStack(spacing: 10) {
            Image(systemName: meta.kind.isPlist ? "list.bullet.rectangle" : "doc")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.name).font(.footnote)
                Text("\(meta.kind.rawValue) · \(ByteCountFormatter.string(fromByteCount: meta.size, countStyle: .file))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func refresh() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: app.workspace.imports,
                                                includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        files = urls.map { FileInspector.meta(for: $0) }
            .sorted { $0.name < $1.name }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                if scoped { PathGuard.registerGrantedRoot(url) }
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let destination = app.workspace.imports.appendingPathComponent(url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    app.log.append(.success, "已导入 \(url.lastPathComponent)")
                } catch {
                    errorText = error.localizedDescription
                    app.log.append(.error, "导入失败：\(error.localizedDescription)")
                }
            }
            refresh()
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }
}

enum SystemProbe {
    static let candidates = [
        "/private/var/mobile/Containers/Data/Application",
        "/private/var/containers/Shared/SystemGroup",
        "/private/var/preferences",
        "/System/Library/CoreServices/SystemVersion.plist"
    ]

    static func describe(_ path: String) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return "不存在或不可见"
        }
        if isDir.boolValue {
            let listable = (try? fm.contentsOfDirectory(atPath: path)) != nil
            return listable ? "可列出" : "存在但无列出权限"
        }
        return fm.isReadableFile(atPath: path) ? "可读" : "存在但无读取权限"
    }
}
