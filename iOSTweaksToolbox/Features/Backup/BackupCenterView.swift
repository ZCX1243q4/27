//
//  BackupCenterView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct BackupCenterView: View {
    @EnvironmentObject private var app: AppState
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(app.backups.records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.id).font(.system(.caption, design: .monospaced))
                            Spacer()
                            if app.backups.verify(record) {
                                StatusBadge(text: "校验通过", tint: .green)
                            } else {
                                StatusBadge(text: "校验失败", tint: .red)
                            }
                        }
                        Text(record.originalPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file))
                            Text("·")
                            Text(record.createdAt.formatted(date: .abbreviated, time: .standard))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                        HStack(spacing: 10) {
                            Button("恢复") { restore(record) }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            Button("删除", role: .destructive) {
                                try? app.backups.delete(record)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("快照（\(app.backups.records.count)）")
            } footer: {
                Text("每次写入前自动创建。恢复前会先给当前内容再做一次快照。")
            }

            Section {
                Button {
                    exportZip()
                } label: {
                    Label("导出工作区为 ZIP", systemImage: "archivebox")
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("备份与恢复")
    }

    private func restore(_ record: BackupRecord) {
        do {
            _ = try app.backups.restore(record)
            message = "已恢复 \(record.originalPath)"
            app.log.append(.success, "恢复完成：\(record.originalPath)")
        } catch {
            message = error.localizedDescription
            app.log.append(.error, "恢复失败：\(error.localizedDescription)")
        }
    }

    private func exportZip() {
        let fm = FileManager.default
        let target = app.workspace.root.appendingPathComponent("TweaksToolbox-\(EventLog.stamp()).zip")
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: app.workspace.root,
                               options: [.forUploading],
                               error: &error) { tempURL in
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: tempURL, to: target)
        }
        if let error {
            message = "导出失败：\(error.localizedDescription)"
        } else {
            message = "已导出：\(target.path)"
            app.log.append(.success, "工作区 ZIP 已导出：\(target.lastPathComponent)")
        }
    }
}
