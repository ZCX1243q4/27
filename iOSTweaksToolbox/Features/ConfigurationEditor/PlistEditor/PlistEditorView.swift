//
//  PlistEditorView.swift
//  iOSTweaksToolbox
//
//  真实的 plist 读取 / 编辑 / 校验 / 带快照保存。
//

import SwiftUI
import UniformTypeIdentifiers

struct PlistEditorView: View {
    let url: URL
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var document: PlistDocument?
    @State private var rootNode: PlistNode?
    @State private var format: PlistFormat = .xml
    @State private var query = ""
    @State private var searchValues = true
    @State private var hits: [String] = []
    @State private var errorText: String?
    @State private var pendingDiff: [DiffItem]?
    @State private var pendingObject: Any?
    @State private var undoStack: [Any] = []
    @State private var redoStack: [Any] = []
    @State private var dirty = false

    var body: some View {
        Group {
            if let rootNode {
                editor(rootNode)
            } else if let errorText {
                EmptyStateView(symbol: "exclamationmark.triangle", title: "无法打开", message: errorText)
            } else {
                ProgressView("读取中…")
            }
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .toolbar { toolbar }
        .sheet(item: Binding(get: { pendingDiff.map { DiffPayload(items: $0) } },
                             set: { if $0 == nil { pendingDiff = nil; pendingObject = nil } })) { payload in
            NavigationStack {
                DiffView(items: payload.items)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { pendingDiff = nil; pendingObject = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("确认保存") { commit(document?.root, new: pendingObject) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
            }
        }
    }

    private func editor(_ node: PlistNode) -> some View {
        List {
            Section {
                KeyValueRow(key: "路径", value: url.path, mono: true)
                KeyValueRow(key: "格式", value: format.rawValue)
                KeyValueRow(key: "可写", value: FileManager.default.isWritableFile(atPath: url.path) ? "是" : "否")
                Picker("保存格式", selection: $format) {
                    ForEach(PlistFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                KeyValueRow(key: "大小",
                            value: ByteCountFormatter.string(fromByteCount: FileInspector.meta(for: url).size,
                                                             countStyle: .file))
            }

            Section("搜索") {
                HStack {
                    TextField("键或值", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("值", isOn: $searchValues).labelsHidden()
                    Button("搜索") {
                        hits = PlistService.search(node.toAny(), query: query, searchValues: searchValues)
                    }
                    .buttonStyle(.bordered)
                }
                if !hits.isEmpty {
                    ForEach(hits.prefix(40), id: \.self) { path in
                        Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }

            Section("内容") {
                PlistNodeView(node: node, depth: 0, onDelete: nil)
            }

            Section {
                Button("添加根级子项") {
                    pushUndo()
                    node.addChild()
                    dirty = true
                }
                Button("预览保存差异") {
                    guard let current = document?.root else { return }
                    let edited = node.toAny()
                    let items = DiffEngine.diff(old: current, new: edited)
                    pendingObject = edited
                    pendingDiff = items.isEmpty ? [DiffItem(path: "/", kind: .changed, oldValue: "无变化", newValue: "无变化")] : items
                }
                .disabled(!FileManager.default.isWritableFile(atPath: url.path))
            } footer: {
                Text("保存前会自动为原文件创建快照；写入失败会立即回滚。")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("撤销") { undo() }.disabled(undoStack.isEmpty)
                Button("重做") { redo() }.disabled(redoStack.isEmpty)
                Divider()
                Button("重新加载") { load() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - 操作

    private func load() {
        do {
            let doc = try PlistService.load(url: url)
            document = doc
            format = doc.format
            rootNode = PlistNode(key: "", value: doc.root)
            errorText = nil
            dirty = false
            app.log.append(.success, "已读取 plist：\(url.lastPathComponent)（\(doc.format.rawValue)）")
        } catch {
            errorText = error.localizedDescription
            app.log.append(.error, "读取 plist 失败：\(error.localizedDescription)")
        }
        _ = document
    }

    private func pushUndo() {
        if let root = document?.root {
            undoStack.append(root)
            redoStack.removeAll()
        }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        if let current = document?.root { redoStack.append(current) }
        document?.root = previous
        rootNode = PlistNode(key: "", value: previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        if let current = document?.root { undoStack.append(current) }
        document?.root = next
        rootNode = PlistNode(key: "", value: next)
    }

    private func commit(_ old: Any?, new: Any?) {
        guard let new else { return }
        do {
            try PlistService.save(object: new, to: url, format: format, backups: app.backups)
            document?.root = new
            rootNode = PlistNode(key: "", value: new)
            dirty = false
            pendingDiff = nil
            pendingObject = nil
            app.log.append(.success, "已保存并校验：\(url.path)")
        } catch {
            app.log.append(.error, "保存失败：\(error.localizedDescription)")
        }
    }
}

struct DiffPayload: Identifiable {
    var id = UUID()
    var items: [DiffItem]
}
