//
//  DeviceIdentityView.swift
//  iOSTweaksToolbox
//
//  逐 App 设备身份配置。这里记录的是"目标值"，
//  并不代表系统已经对目标 App 生效。
//

import SwiftUI

struct DeviceIdentityView: View {
    @EnvironmentObject private var app: AppState
    @State private var editing: IdentityTarget?
    @State private var real: RealIdentity?

    var body: some View {
        List {
            Section {
                Text("每个 App 可以保存一份独立的目标设备身份。iOS 未越狱环境下，普通 App 无法拦截其他进程的系统 API 调用，因此这份配置不会改变目标 App 实际读到的值；它用于研究、对照与后续实验。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let real {
                Section("真实值（本进程读取）") {
                    KeyValueRow(key: "型号", value: real.marketingName)
                    KeyValueRow(key: "ProductType", value: real.productType, mono: true)
                    KeyValueRow(key: "iOS", value: "\(real.systemVersion) (\(real.buildNumber))")
                    KeyValueRow(key: "逻辑尺寸", value: "\(Int(real.logicalWidth)) × \(Int(real.logicalHeight))")
                    KeyValueRow(key: "原生像素", value: "\(Int(real.nativeWidth)) × \(Int(real.nativeHeight))")
                    KeyValueRow(key: "Scale", value: "\(real.scale)")
                }
            }

            Section("已配置的目标 App") {
                ForEach(app.identityStore.targets) { target in
                    Button {
                        editing = target
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.displayName.isEmpty ? target.bundleID : target.displayName)
                                    .font(.footnote)
                                Text(target.bundleID)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if target.enabled {
                                StatusBadge(text: "已启用配置", tint: .orange)
                            } else {
                                Text(target.marketingName)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        app.identityStore.remove(app.identityStore.targets[index])
                    }
                }
                Button {
                    editing = IdentityTarget(bundleID: "", displayName: "")
                } label: {
                    Label("新增目标 App", systemImage: "plus.circle")
                }
            }

            Section {
                Text("配置字段覆盖型号、ProductType、架构、系统版本、Build 与屏幕参数。只改其中一项通常不足以改变一个 App 的整体判断——真实设备信息分散在多个接口里，这也是本模块把各项分开管理的原因。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设备身份管理")
        .task { real = IdentityStore.realIdentity() }
        .sheet(item: $editing) { target in
            NavigationStack {
                IdentityEditView(target: target) { updated in
                    app.identityStore.upsert(updated)
                    app.log.append(.info, "已保存身份配置：\(updated.bundleID)")
                }
            }
        }
    }
}

struct IdentityEditView: View {
    @State var target: IdentityTarget
    var onSave: (IdentityTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [IdentityComparisonRow] = []
    @State private var real: RealIdentity?

    var body: some View {
        Form {
            Section("目标 App") {
                TextField("Bundle ID", text: $target.bundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                TextField("显示名称", text: $target.displayName)
                Toggle("启用这份配置", isOn: $target.enabled)
            }

            Section("设备型号") {
                TextField("市场名称，例如 iPhone 17 Pro", text: $target.marketingName)
                TextField("ProductType，例如 iPhone18,1", text: $target.productType)
                    .font(.system(.footnote, design: .monospaced))
                TextField("架构", text: $target.architecture)
                    .font(.system(.footnote, design: .monospaced))
            }

            Section("系统版本") {
                TextField("iOS 版本", text: $target.systemVersion)
                TextField("Build", text: $target.buildNumber)
            }

            Section("屏幕参数") {
                TextField("逻辑宽", value: $target.logicalWidth, format: .number)
                    .keyboardType(.decimalPad)
                TextField("逻辑高", value: $target.logicalHeight, format: .number)
                    .keyboardType(.decimalPad)
                TextField("原生宽", value: $target.nativeWidth, format: .number)
                    .keyboardType(.decimalPad)
                TextField("原生高", value: $target.nativeHeight, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Scale", value: $target.scale, format: .number)
                    .keyboardType(.decimalPad)
            }

            Section {
                Button("用 iPhone 17 Pro 参数填充") { fill("iPhone18,1", "iPhone 17 Pro", 402, 874, 1206, 2622, 3) }
                Button("用 iPhone 16 Pro Max 参数填充") { fill("iPhone17,2", "iPhone 16 Pro Max", 440, 956, 1320, 2868, 3) }
                Button("用 iPhone 16e 参数填充") { fill("iPhone17,5", "iPhone 16e", 390, 844, 1170, 2532, 3) }
            } header: {
                Text("快捷填充")
            } footer: {
                Text("这些数值只写进本工具的目标配置，不会改变系统。")
            }

            if !rows.isEmpty {
                Section("真实值 vs 目标值") {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.field)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("真实 \(row.realValue)").font(.caption2).foregroundStyle(.secondary)
                                Text("目标 \(row.targetValue)").font(.caption2)
                                    .foregroundStyle(row.matches ? .green : .orange)
                            }
                        }
                    }
                }
            }

            Section {
                TextField("备注", text: $target.note, axis: .vertical)
            }
        }
        .navigationTitle(target.bundleID.isEmpty ? "新增目标" : "编辑目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(target)
                    dismiss()
                }
                .disabled(target.bundleID.isEmpty)
            }
        }
        .task {
            real = IdentityStore.realIdentity()
            refresh()
        }
        .onChange(of: target.marketingName) { _, _ in refresh() }
        .onChange(of: target.productType) { _, _ in refresh() }
    }

    private func refresh() {
        guard let real else { return }
        rows = IdentityStore.comparison(real: real, target: target)
    }

    private func fill(_ product: String, _ name: String, _ lw: Double, _ lh: Double,
                      _ nw: Double, _ nh: Double, _ scale: Double) {
        target.productType = product
        target.marketingName = name
        target.logicalWidth = lw
        target.logicalHeight = lh
        target.nativeWidth = nw
        target.nativeHeight = nh
        target.scale = scale
        target.systemVersion = real?.systemVersion ?? OSCompatibility.systemVersion
        target.buildNumber = real?.buildNumber ?? OSCompatibility.build
        if target.architecture.isEmpty { target.architecture = "arm64e" }
        refresh()
    }
}
