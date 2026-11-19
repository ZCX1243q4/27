//
//  GestaltView.swift
//  iOSTweaksToolbox
//
//  MobileGestalt 缓存：读取、键值编辑、备份、差异预览与安全写入。
//

import SwiftUI

struct GestaltView: View {
    @EnvironmentObject private var app: AppState

    @State private var snapshot: GestaltSnapshot?
    @State private var status = "未读取"
    @State private var keys: [GestaltKeyRow] = []
    @State private var editing: GestaltKeyRow?
    @State private var pendingEdits: [String: Any] = [:]
    @State private var diffItems: [DiffItem] = []
    @State private var showDiff = false
    @State private var search = ""

    private var filtered: [GestaltKeyRow] {
        guard !search.isEmpty else { return keys }
        return keys.filter {
            $0.key.localizedCaseInsensitiveContains(search) ||
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.value.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    StatusBadge(text: worseQueryStatus.0, tint: worseQueryStatus.1)
                    Spacer()
                    Button("获取访问令牌") { grantAccess() }
                        .font(.caption)
                }
                KeyValueRow(key: "App Group", value: WorseQuery.shared.group.isEmpty ? "无" : WorseQuery.shared.group, mono: true)
                KeyValueRow(key: "系统文件", value: MGPath.systemGestalt, mono: true)
                KeyValueRow(key: "状态", value: status)
                if let snapshot {
                    KeyValueRow(key: "大小", value: "\(snapshot.size) 字节")
                    KeyValueRow(key: "SHA-256", value: String(snapshot.sha256.prefix(24)) + "…", mono: true)
                    KeyValueRow(key: "可写", value: snapshot.writable ? "是" : "否")
                }
            } header: {
                Text("访问状态")
            } footer: {
                Text("worse_query 需要签名保留 App Group 权利。iOS 27.3 beta 2 起 Apple 已修复该技术，此时会显示拒绝。")
            }

            Section {
                Button {
                    load()
                } label: {
                    Label("读取系统 MobileGestalt", systemImage: "arrow.down.doc")
                }
                Button {
                    backupOriginal()
                } label: {
                    Label("备份为原始副本", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(snapshot == nil)
                if let original = GestaltService.loadOriginal(workspace: app.workspace) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("原始备份").font(.footnote)
                            Text("SHA-256 \(original.digestOK ? "校验通过" : "校验失败")")
                                .font(.caption2)
                                .foregroundStyle(original.digestOK ? .green : .red)
                        }
                        Spacer()
                        Button("还原") { restore(original.data) }
                            .font(.caption)
                    }
                }
            } header: {
                Text("备份")
            }

            if !keys.isEmpty {
                Section("搜索") {
                    TextField("键、名称或值", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("已知键（\(filtered.count)）") {
                    ForEach(filtered) { row in
                        Button { editing = row } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(row.name).font(.footnote)
                                    Spacer()
                                    if pendingEdits[row.key] != nil {
                                        StatusBadge(text: "待写入", tint: .orange)
                                    }
                                }
                                Text(row.key)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(row.value)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            if !pendingEdits.isEmpty {
                Section {
                    Button {
                        previewDiff()
                    } label: {
                        Label("预览变更（\(pendingEdits.count) 处）", systemImage: "arrow.left.arrow.right")
                    }
                } footer: {
                    Text("写入前会展示逐键对比，写入时先保存快照，写后读回校验，失败自动回滚。")
                }
            }

            Section("缓存数据") {
                if let snapshot, let dict = GestaltService.parse(snapshot.data) {
                    KeyValueRow(key: "CacheVersion", value: "\(dict["CacheVersion"] ?? "—")")
                    KeyValueRow(key: "CacheUUID", value: "\(dict["CacheUUID"] ?? "—")", mono: true)
                    if let cacheData = dict["CacheData"] as? Data {
                        KeyValueRow(key: "CacheData", value: "\(cacheData.count) 字节")
                    }
                    if let extra = dict["CacheExtra"] as? [String: Any] {
                        KeyValueRow(key: "CacheExtra", value: "\(extra.count) 个键")
                    }
                } else {
                    Text("尚未读取").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("MobileGestalt")
        .sheet(item: $editing) { row in
            NavigationStack {
                GestaltEditView(row: row) { key, value in
                    pendingEdits[key] = value
                    app.log.info("待写入 \(row.name)：\(key) = \(value)")
                }
            }
        }
        .sheet(isPresented: $showDiff) {
            NavigationStack {
                DiffView(items: diffItems)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showDiff = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("确认写入") {
                                showDiff = false
                                apply()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
            }
        }
    }

    private var worseQueryStatus: (String, Color) {
        if !WorseQuery.shared.hasGroup { return ("无 App Group", .red) }
        if snapshot?.writable == true { return ("可读写", .green) }
        if snapshot != nil { return ("只读", .orange) }
        return ("待检测", .gray)
    }

    private func grantAccess() {
        let result = WorseQuery.shared.grant(MGPath.systemGestalt)
        status = result.message
        app.log.append(result.ok ? .success : .error, result.message)
        load()
    }

    private func load() {
        guard let snap = GestaltService.readSystem() else {
            status = "无法读取系统 MobileGestalt（需要先获取访问令牌）"
            app.log.append(.warning, status)
            return
        }
        snapshot = snap
        keys = GestaltKeyRow.rows(from: snap.data)
        status = "已读取 \(snap.size) 字节"
        app.log.append(.success, "读取 MobileGestalt：\(snap.size) 字节，\(keys.count) 个已知键")
    }

    private func backupOriginal() {
        guard let snapshot else { return }
        do {
            let digest = try GestaltService.saveOriginal(snapshot.data, workspace: app.workspace)
            app.log.append(.success, "已保存原始副本，SHA-256 \(digest.prefix(16))…")
        } catch {
            app.log.append(.error, "备份失败：\(error.localizedDescription)")
        }
    }

    private func restore(_ data: Data) {
        do {
            try GestaltService.writeInPlace(data, to: URL(fileURLWithPath: MGPath.systemGestalt))
            app.log.append(.success, "已还原原始 MobileGestalt，重启后完全生效")
            load()
        } catch {
            app.log.append(.error, "还原失败：\(error.localizedDescription)")
        }
    }

    private func previewDiff() {
        guard let snapshot, let dict = GestaltService.parse(snapshot.data) else { return }
        var updated = dict
        var extra = (dict["CacheExtra"] as? [String: Any]) ?? [:]
        for (key, value) in pendingEdits { extra[key] = value }
        updated["CacheExtra"] = extra
        diffItems = DiffEngine.diff(old: dict, new: updated)
        showDiff = true
    }

    private func apply() {
        guard let snapshot, var dict = GestaltService.parse(snapshot.data) else { return }
        var extra = (dict["CacheExtra"] as? [String: Any]) ?? [:]
        for (key, value) in pendingEdits { extra[key] = value }
        dict["CacheExtra"] = extra
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict,
                                                             format: .binary,
                                                             options: 0) else {
            app.log.append(.error, "序列化失败，已中止写入")
            return
        }
        do {
            try GestaltService.writeInPlace(data, to: URL(fileURLWithPath: MGPath.systemGestalt))
            pendingEdits.removeAll()
            app.log.append(.success, "已写入并校验通过，重启设备后生效")
            load()
        } catch {
            app.log.append(.error, "写入失败：\(error.localizedDescription)")
        }
    }
}

struct GestaltKeyRow: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var value: String
    var raw: Any?

    static func rows(from data: Data) -> [GestaltKeyRow] {
        guard let dict = GestaltService.parse(data),
              let extra = dict["CacheExtra"] as? [String: Any] else { return [] }
        return extra.keys.sorted().map { key in
            let raw = extra[key]
            return GestaltKeyRow(key: key,
                                 name: MGKeyNames.name(for: key),
                                 value: PlistService.preview(of: raw as Any),
                                 raw: raw)
        }
    }
}

struct GestaltEditView: View {
    var row: GestaltKeyRow
    var onCommit: (String, Any) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var boolValue = false
    @State private var intValue = "0"
    @State private var stringValue = ""
    @State private var kind: Kind = .boolean

    enum Kind: String, CaseIterable { case boolean = "布尔", integer = "整数", string = "字符串" }

    var body: some View {
        Form {
            Section("键") {
                KeyValueRow(key: "名称", value: row.name)
                KeyValueRow(key: "键名", value: row.key, mono: true)
                KeyValueRow(key: "当前值", value: row.value)
            }
            Section("新值") {
                Picker("类型", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                switch kind {
                case .boolean:
                    Toggle("值", isOn: $boolValue)
                case .integer:
                    TextField("整数", text: $intValue).keyboardType(.numbersAndPunctuation)
                case .string:
                    TextField("字符串", text: $stringValue)
                }
            }
        }
        .navigationTitle(row.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("设为待写入") {
                    switch kind {
                    case .boolean: onCommit(row.key, boolValue ? 1 : 0)
                    case .integer: onCommit(row.key, Int(intValue) ?? 0)
                    case .string: onCommit(row.key, stringValue)
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            if let number = row.raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                kind = .boolean
                boolValue = number.boolValue
            } else if let number = row.raw as? NSNumber {
                kind = .integer
                intValue = number.stringValue
            } else if let string = row.raw as? String {
                kind = .string
                stringValue = string
            }
        }
    }
}

enum MGKeyNames {
    private static let table: [String: String] = [
        "YlEtTtHlNesRBMal1CqRaA": "灵动岛支持 DeviceSupportsDynamicIsland",
        "2OOJf1VhaM7NxfRok3HbWQ": "全天候显示 AOD",
        "j8/Omm6s1lsmTDFsXjsBfA": "AOD 时间显示",
        "ykpu7qyhqFweVMKtxNylWA": "AOD 鲜艳度",
        "yZf3GTRMGTuwSV/lD7Cagw": "轻点唤醒 DeviceSupportsTapToWake",
        "97JDvERpVwO+GHtthIh7hA": "监管型号 RegulatoryModelNumber",
        "h9jDsbgj7xIVeIQ8S3/X3Q": "ProductType",
        "oPeik/9e8lQWMszEjbPzng": "ArtworkTraits（含 Subtype）",
        "Z/dqyWS6OZTRy10UcmUAhw": "设备产品名称",
        "bbtR9jQx50Fv5Af/affNtA": "设备市场名称",
        "SAGvsp6O6kAQ4fEfDJpC4Q": "液态玻璃低功耗渲染",
        "37NVydb//GP/GrhuTN+exg": "80% 充电上限",
        "QHxt+hGLaBPbQJbXiUJX3w": "开机提示音",
        "A62OafQ85EJAiiqKn4agtg": "Apple 智能总开关",
        "XNCjqOupLM/S8fNyxRNQTA": "相册「消除」",
        "YgYIIViDt1kgzyIsIV61vA": "备忘录手写体合成",
        "rb2tKZxlj0Gm2tBmUQSLqQ": "音频智能 Audio Intelligence",
        "M1n2sAqf33NAOgZRGxQYBA": "个人实时翻译",
        "h63QSdBCiT/z0WU6rdQv6Q": "地区代码 RegionCode",
        "yK+xavymRGZ3xWc1tb8XDg": "系统销售地区",
        "HCzWusHQwZDea6nNhaKndw": "车祸检测",
        "CwvKxM2cEogD3p+HYgaW0Q": "相机控制按键",
        "cT44WE1EohiwRzhsZ8xEsw": "操作按钮",
        "qeaj75wk3HF4DwQ8qbIi7g": "台前调度 / 增强多任务",
        "uKc7FPnEO++lVhHWHFlGbQ": "iPad 设备模式",
        "iyfxmLogGVIaH7aEgqwcIA": "green-tea（CacheData 槽位）",
        "4snMZS8LJkSctKypt2m+xA": "not-green-tea（CacheData 槽位）",
        "hiHut/WR+B9Lx/vd0WyeNg": "wapi（CacheData 槽位）"
    ]

    static func name(for key: String) -> String {
        table[key] ?? key
    }
}
