//
//  DiagnosticsView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var app: AppState
    @State private var filter: LogLevel?

    private var filtered: [LogEntry] {
        guard let filter else { return app.log.entries.reversed() }
        return app.log.entries.reversed().filter { $0.level == filter }
    }

    var body: some View {
        List {
            Section {
                Picker("级别", selection: $filter) {
                    Text("全部").tag(LogLevel?.none)
                    Text("信息").tag(LogLevel?.some(.info))
                    Text("成功").tag(LogLevel?.some(.success))
                    Text("警告").tag(LogLevel?.some(.warning))
                    Text("错误").tag(LogLevel?.some(.error))
                }
                .pickerStyle(.segmented)
            }

            Section("事件") {
                if filtered.isEmpty {
                    EmptyStateView(symbol: "text.alignleft", title: "暂无记录", message: "操作后会在这里留下真实日志")
                } else {
                    ForEach(Array(filtered.prefix(400))) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: entry.level.symbol)
                                    .foregroundStyle(tint(entry.level))
                                Text(entry.level.label)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(tint(entry.level))
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.message)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("诊断与日志")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("导出日志") {
                        if let url = try? app.log.export(to: app.workspace.journals) {
                            app.log.append(.success, "日志已导出：\(url.path)")
                        }
                    }
                    Button("导出能力矩阵") {
                        let url = app.workspace.journals.appendingPathComponent("capabilities.txt")
                        try? app.capabilities.text().write(to: url, atomically: true, encoding: .utf8)
                        app.log.append(.success, "能力矩阵已导出：\(url.path)")
                    }
                    Button("清空日志", role: .destructive) { app.log.clear() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func tint(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
