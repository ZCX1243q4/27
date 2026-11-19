//
//  JSONEditorWorkspaceView.swift
//  iOSTweaksToolbox
//
//  JSON 编辑器：格式化、校验、键值搜索与替换，保存带快照。
//

import SwiftUI

struct JSONEditorWorkspaceView: View {
    var initialURL: URL?
    @EnvironmentObject private var app: AppState

    @State private var text = ""
    @State private var currentURL: URL?
    @State private var validation: String?
    @State private var isValid = false
    @State private var findText = ""
    @State private var replaceText = ""

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(6)
                .onChange(of: text) { _, _ in validate() }
            statusBar
        }
        .navigationTitle(currentURL?.lastPathComponent ?? "JSON 编辑器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let initialURL { load(initialURL) } }
    }

    private var editorToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button("格式化") { format() }
                Button("压缩") { minify() }
                Button("校验") { validate(force: true) }
                Button("保存") { save() }
                    .disabled(currentURL == nil || !isValid)
                Divider().frame(height: 20)
                TextField("查找", text: $findText).frame(width: 90)
                    .textFieldStyle(.roundedBorder)
                TextField("替换", text: $replaceText).frame(width: 90)
                    .textFieldStyle(.roundedBorder)
                Button("全部替换") { replaceAll() }
                    .disabled(findText.isEmpty)
            }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: isValid ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(isValid ? .green : .orange)
            Text(validation ?? "尚未校验")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(text.count) 字符").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    // MARK: - 操作

    private func load(_ url: URL) {
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            currentURL = url
            validate(force: true)
            app.log.append(.success, "已读取 JSON：\(url.lastPathComponent)")
        } catch {
            validation = error.localizedDescription
            app.log.append(.error, "读取 JSON 失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    private func validate(force: Bool = false) -> Bool {
        guard let data = text.data(using: .utf8) else {
            isValid = false
            validation = "编码错误"
            return false
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            isValid = true
            let keys = (object as? [String: Any])?.count ?? (object as? [Any])?.count ?? 0
            validation = "合法 JSON · 顶层 \(keys) 项"
        } catch {
            isValid = false
            validation = error.localizedDescription
        }
        return isValid
    }

    private func format() {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let result = String(data: pretty, encoding: .utf8) else {
            validation = "格式化失败：内容不是合法 JSON"
            return
        }
        text = result
        validate()
    }

    private func minify() {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let compact = try? JSONSerialization.data(withJSONObject: object,
                                                        options: [.sortedKeys, .withoutEscapingSlashes]),
              let result = String(data: compact, encoding: .utf8) else {
            validation = "压缩失败：内容不是合法 JSON"
            return
        }
        text = result
        validate()
    }

    private func replaceAll() {
        guard !findText.isEmpty else { return }
        let count = text.components(separatedBy: findText).count - 1
        text = text.replacingOccurrences(of: findText, with: replaceText)
        validate()
        app.log.append(.info, "已替换 \(count) 处「\(findText)」")
    }

    private func save() {
        guard let currentURL else { return }
        guard validate() else { return }
        do {
            try PathGuard.check(currentURL.path)
            guard let data = text.data(using: .utf8) else { return }
            try data.write(to: currentURL, options: .atomic)
            app.log.append(.success, "JSON 已保存：\(currentURL.path)")
        } catch {
            app.log.append(.error, "保存失败：\(error.localizedDescription)")
        }
    }
}
