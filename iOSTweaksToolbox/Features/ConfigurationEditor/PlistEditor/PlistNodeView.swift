//
//  PlistNodeView.swift
//  iOSTweaksToolbox
//
//  plist 树的递归编辑器。
//

import SwiftUI

struct PlistNodeView: View {
    @Bindable var node: PlistNode
    var depth: Int
    var onDelete: (() -> Void)?

    var body: some View {
        if node.type == .dictionary || node.type == .array {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { child in
                    PlistNodeView(node: child, depth: depth + 1) {
                        node.removeChild(id: child.id)
                    }
                }
                Button {
                    node.addChild()
                } label: {
                    Label(node.type == .array ? "添加元素" : "添加键", systemImage: "plus.circle")
                        .font(.footnote)
                }
            } label: {
                containerLabel
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if !node.key.isEmpty {
                        Text(node.key)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(PlistValueType.allCases) { type in
                            Button(type.rawValue) { node.convert(to: type) }
                        }
                    } label: {
                        StatusBadge(text: node.type.rawValue, tint: .blue)
                    }
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                valueEditor
            }
            .padding(.vertical, 2)
        }
    }

    private var containerLabel: some View {
        HStack {
            Text(node.key.isEmpty ? "(根)" : node.key)
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            StatusBadge(text: "\(node.type.rawValue) · \(node.children.count)", tint: .purple)
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch node.type {
        case .string, .integer, .real:
            TextField("值", text: $node.stringValue, axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(node.type == .string ? .default : .numbersAndPunctuation)
        case .boolean:
            Toggle("值", isOn: $node.boolValue)
                .font(.system(.footnote, design: .monospaced))
        case .date:
            DatePicker("值", selection: $node.dateValue, displayedComponents: [.date, .hourAndMinute])
                .font(.system(.footnote, design: .monospaced))
        case .data:
            HStack {
                Text("\(node.dataValue.count) 字节")
                    .font(.system(.footnote, design: .monospaced))
                Spacer()
                Text(node.dataValue.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .dictionary, .array:
            EmptyView()
        }
    }
}
