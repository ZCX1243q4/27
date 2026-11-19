//
//  HexWorkspaceView.swift
//  iOSTweaksToolbox
//
//  真实二进制读取与就地字节修改。
//

import SwiftUI

struct HexWorkspaceView: View {
    var initialURL: URL?
    @EnvironmentObject private var app: AppState

    @State private var currentURL: URL?
    @State private var data = Data()
    @State private var pageSize = 4096
    @State private var pageIndex = 0
    @State private var searchText = ""
    @State private var matches: [Int] = []
    @State private var edits: [Int: UInt8] = [:]
    @State private var status = ""

    private var pageCount: Int {
        max(1, Int(ceil(Double(data.count) / Double(pageSize))))
    }

    private var pageRange: Range<Int> {
        let start = min(pageIndex * pageSize, data.count)
        let end = min(start + pageSize, data.count)
        return start..<end
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rows, id: \.offset) { row in
                        rowView(row)
                    }
                }
                .padding(8)
            }
            Divider()
            footer
        }
        .navigationTitle(currentURL?.lastPathComponent ?? "Hex 编辑器")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let initialURL { load(initialURL) } }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("上一页") { pageIndex = max(0, pageIndex - 1) }
                    .disabled(pageIndex == 0)
                Text("\(pageIndex + 1) / \(pageCount)")
                    .font(.caption.monospacedDigit())
                Button("下一页") { pageIndex = min(pageCount - 1, pageIndex + 1) }
                    .disabled(pageIndex >= pageCount - 1)
                Spacer()
                Picker("分页", selection: $pageSize) {
                    Text("1 KB").tag(1024)
                    Text("4 KB").tag(4096)
                    Text("16 KB").tag(16384)
                }
                .pickerStyle(.menu)
            }
            HStack(spacing: 8) {
                TextField("字节搜索（如 62 70 6c 69 73 74 或文本）", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)
                Button("搜索") { performSearch() }
                    .font(.caption)
            }
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("命中 \(matches.count) 处").font(.caption2).foregroundStyle(.secondary)
                        ForEach(matches.prefix(50), id: \.self) { offset in
                            Button(String(format: "0x%llX", offset)) {
                                pageIndex = offset / pageSize
                            }
                            .font(.system(.caption2, design: .monospaced))
                        }
                    }
                }
            }
        }
        .font(.footnote)
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if !edits.isEmpty {
                Text("\(edits.count) 处待写入").font(.caption2).foregroundStyle(.orange)
                Button("写入文件") { commit() }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - 行视图

    private struct HexRow: Identifiable {
        var id: Int { offset }
        var offset: Int
        var bytes: [UInt8]
    }

    private var rows: [HexRow] {
        guard !data.isEmpty else { return [] }
        var result: [HexRow] = []
        var offset = pageRange.lowerBound
        while offset < pageRange.upperBound {
            let end = min(offset + 16, pageRange.upperBound)
            result.append(HexRow(offset: offset, bytes: Array(data[offset..<end])))
            offset = end
        }
        return result
    }

    private func rowView(_ row: HexRow) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%08llX", row.offset))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(Array(row.bytes.enumerated()), id: \.offset) { pair in
                    let absolute = row.offset + pair.offset
                    let value = edits[absolute] ?? pair.element
                    Button {
                        edit(offset: absolute, current: value)
                    } label: {
                        Text(String(format: "%02X", value))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(edits[absolute] != nil ? .orange : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(ascii(row.bytes))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func ascii(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            (byte >= 32 && byte < 127) ? String(UnicodeScalar(byte)) : "·"
        }.joined()
    }

    // MARK: - 操作

    private func load(_ url: URL) {
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
            currentURL = url
            pageIndex = 0
            edits.removeAll()
            status = "已读取 \(data.count) 字节"
            app.log.append(.success, "Hex 载入：\(url.lastPathComponent)（\(data.count) 字节）")
        } catch {
            status = "读取失败：\(error.localizedDescription)"
            app.log.append(.error, status)
        }
    }

    private func edit(offset: Int, current: UInt8) {
        let alert = UIAlertController(title: String(format: "偏移 0x%llX", offset),
                                      message: "输入新的十六进制字节（00–FF）",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.text = String(format: "%02X", current)
            field.keyboardType = .asciiCapable
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            guard let text = alert.textFields?.first?.text,
                  let byte = UInt8(text.trimmingCharacters(in: .whitespaces), radix: 16) else {
                status = "输入不是合法十六进制字节"
                return
            }
            edits[offset] = byte
            status = "待写入：0x\(String(format: "%llX", offset)) → \(String(format: "%02X", byte))"
        })
        topMostViewController()?.present(alert, animated: true)
    }

    private func performSearch() {
        matches.removeAll()
        guard !searchText.isEmpty, !data.isEmpty else { return }
        let needle: [UInt8]
        let tokens = searchText.split(separator: " ")
        if tokens.count > 1, tokens.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) {
            needle = tokens.compactMap { UInt8($0, radix: 16) }
        } else {
            needle = Array(searchText.utf8)
        }
        guard !needle.isEmpty else { return }
        let bytes = [UInt8](data)
        if bytes.count >= needle.count {
            for index in 0...(bytes.count - needle.count) {
                if Array(bytes[index..<(index + needle.count)]) == needle {
                    matches.append(index)
                    if matches.count >= 500 { break }
                }
            }
        }
        status = "搜索完成，命中 \(matches.count) 处"
    }

    private func commit() {
        guard let currentURL, !edits.isEmpty else { return }
        do {
            var newData = data
            for (offset, byte) in edits where offset < newData.count {
                newData[offset] = byte
            }
            try BackupServiceSnapshotHelper.snapshotAndWrite(data: newData,
                                                             to: currentURL,
                                                             backups: app.backups)
            data = newData
            edits.removeAll()
            status = "已写入 \(currentURL.lastPathComponent)（写入前已快照）"
            app.log.append(.success, "Hex 写入：\(currentURL.path)")
        } catch {
            status = "写入失败：\(error.localizedDescription)"
            app.log.append(.error, status)
        }
    }

    private func topMostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

enum BackupServiceSnapshotHelper {
    static func snapshotAndWrite(data: Data, to url: URL, backups: BackupService) throws {
        let snapshot = FileManager.default.fileExists(atPath: url.path)
            ? try backups.snapshot(url: url, note: "Hex 写入前快照") : nil
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            if let snapshot { _ = try? backups.restore(snapshot) }
            throw error
        }
    }
}
