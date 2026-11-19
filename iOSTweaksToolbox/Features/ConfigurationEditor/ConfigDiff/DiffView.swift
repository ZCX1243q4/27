//
//  DiffView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct DiffView: View {
    var items: [DiffItem]

    var body: some View {
        List {
            if items.isEmpty {
                EmptyStateView(symbol: "equal.circle", title: "没有差异", message: "两份配置逐键一致")
            } else {
                Section("共 \(items.count) 处差异") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                StatusBadge(text: item.kind.rawValue, tint: tint(item.kind))
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.oldValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.newValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("配置差异")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tint(_ kind: DiffKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .changed: return .orange
        }
    }
}
