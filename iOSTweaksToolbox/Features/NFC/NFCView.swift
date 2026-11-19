//
//  NFCView.swift
//  iOSTweaksToolbox
//
//  NFC 卡片读取与导出。做不到的（卡模拟）写在界面上，不藏。
//

import SwiftUI

struct NFCView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var scanner = NFCScanner()
    @State private var selected: NFCCardRecord?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: NFCAvailability.isSupported ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                        .foregroundStyle(NFCAvailability.isSupported ? .green : .red)
                    Text(NFCAvailability.description).font(.footnote)
                }
                if !NFCAvailability.isSupported {
                    Text("这台设备或当前系统不允许 CoreNFC 读取。")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("设备能力")
            }

            Section {
                Button {
                    scanner.startTagScan()
                } label: {
                    Label(scanner.isScanning ? "扫描中…" : "读取卡片（含 UID）", systemImage: "sensor.tag.radiowaves.forward")
                }
                .disabled(scanner.isScanning || !NFCAvailability.isSupported)

                Button {
                    scanner.startNdefScan()
                } label: {
                    Label("只读 NDEF 内容", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(scanner.isScanning || !NFCAvailability.isSupported)
            } header: {
                Text("读取")
            } footer: {
                Text("「含 UID」会识别 MIFARE / ISO7816 / ISO15693 / FeliCa 并读出卡号；「只读 NDEF」只读写在卡上的标准数据。")
            }

            if let error = scanner.lastError {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }

            Section {
                if scanner.records.isEmpty {
                    EmptyStateView(symbol: "creditcard",
                                   title: "还没有读取记录",
                                   message: "把门禁卡、公交卡、NFC 标签贴到 iPhone 顶部试试")
                } else {
                    ForEach(scanner.records) { record in
                        Button {
                            selected = record
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.uid)
                                    .font(.system(.footnote, design: .monospaced))
                                Text(record.technologies.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(record.scannedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { scanner.delete(scanner.records[index]) }
                    }
                }
            } header: {
                Text("已读取（\(scanner.records.count)）")
            }

            Section {
                Text("""
                关于「把卡复制到手机里」：

                iPhone 没有卡模拟（HCE）能力。CoreNFC 只提供读取，Apple 没有向第三方开放让 iPhone 扮演一张卡片的接口。要把门禁卡、工牌、电梯卡复制成手机刷，必须满足：

                1. 卡是未加密的 MIFARE Classic / Ultralight，且你能拿到扇区密钥；
                2. 手机侧有可编程的安全元件（SE）——安卓的 Host Card Emulation 可以，iPhone 不行；
                3. 或者把数据写进 iPhone 的 SE 里做成 Apple 钱包卡片——这条路需要和发卡方签协议，Apple 只对交通卡、门锁合作厂商开放。

                所以本工具能做的是：把卡片读出来、把内容导出成 JSON，供你离线分析或交给能模拟的设备。真正「让 iPhone 变成这张卡」这一步，在未越狱的 iOS 上没有任何实现路径。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("NFC 卡片")
        .onAppear { scanner.load() }
        .sheet(item: $selected) { record in
            NavigationStack {
                NFCDetailView(record: record)
            }
        }
    }
}

struct NFCDetailView: View {
    var record: NFCCardRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("卡片") {
                KeyValueRow(key: "UID / IDm", value: record.uid, mono: true)
                KeyValueRow(key: "技术", value: record.technologies.joined(separator: ", "))
                KeyValueRow(key: "读取时间", value: record.scannedAt.formatted(date: .abbreviated, time: .standard))
                KeyValueRow(key: "系统信息", value: record.systemInfo)
            }
            if !record.ndefRecords.isEmpty {
                Section("NDEF 记录（\(record.ndefRecords.count)）") {
                    ForEach(record.ndefRecords) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.type.isEmpty ? "(无类型)" : item.type)
                                .font(.system(.caption, design: .monospaced))
                            Text(item.payloadText)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("\(item.payloadSize) 字节 · TNF \(item.typeNameFormat)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("卡片详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }
}
