//
//  DeviceProfileView.swift
//  iOSTweaksToolbox
//
//  真实修改设备几何特征：ArtworkTraits.SubType 决定屏幕几何，
//  ProductType 决定机型标识。这两项是改分辨率 / 挪灵动岛的实际杠杆。
//

import SwiftUI

struct DeviceProfileView: View {
    @EnvironmentObject private var app: AppState

    @State private var subtype = ""
    @State private var deviceName = ""
    @State private var productType = ""
    @State private var currentSubtype: Int?
    @State private var currentName = ""
    @State private var currentProduct = ""
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "当前 SubType", value: currentSubtype.map(String.init) ?? "不存在")
                KeyValueRow(key: "当前产品名", value: currentName.isEmpty ? "—" : currentName)
                KeyValueRow(key: "当前 ProductType", value: currentProduct.isEmpty ? "—" : currentProduct, mono: true)
            } header: {
                Text("设备当前值")
            } footer: {
                Text("这些值来自 com.apple.MobileGestalt.plist 的 CacheExtra。SubType 决定 SpringBoard 使用的屏幕几何特征，ProductType 决定机型标识。")
            }

            Section {
                HStack {
                    Text("SubType").font(.footnote)
                    Spacer()
                    TextField("整数", text: $subtype)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
                TextField("产品名称", text: $deviceName)
                TextField("ProductType", text: $productType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
            } header: {
                Text("目标值")
            }

            Section {
                ForEach(DevicePresets.all) { preset in
                    Button {
                        subtype = String(preset.subtype)
                        productType = preset.productType
                        deviceName = preset.name
                    } label: {
                        HStack {
                            Text(preset.name).font(.footnote)
                            Spacer()
                            Text("\(preset.subtype) · \(preset.productType)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("已知机型参数")
            } footer: {
                Text("选择只会填入目标值，仍需点「写入」才落到系统文件。")
            }

            Section {
                Button {
                    write()
                } label: {
                    Label("写入系统缓存", systemImage: "square.and.arrow.down")
                }
                .disabled(busy)
                Button {
                    refresh()
                } label: {
                    Label("重新读取", systemImage: "arrow.clockwise")
                }
            } footer: {
                if message.isEmpty {
                    Text("写入采用原位覆盖 + F_FULLFSYNC + 读回校验，失败自动回滚。写入后必须注销才生效。")
                } else {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设备几何特征")
        .onAppear { refresh() }
    }

    private func refresh() {
        _ = WorseQuery.shared.grant(MGPath.systemGestalt)
        let profile = GestaltService.readDeviceProfile()
        currentSubtype = profile.subtype
        currentName = profile.deviceName
        currentProduct = profile.productType

        subtype = profile.subtype.map(String.init) ?? ""
        deviceName = profile.deviceName
        productType = profile.productType
    }

    private func write() {
        busy = true
        defer { busy = false }
        let parsedSubtype = Int(subtype.trimmingCharacters(in: .whitespaces))
        do {
            _ = try GestaltService.applyDeviceProfile(subtype: parsedSubtype,
                                                      deviceName: deviceName,
                                                      productType: productType,
                                                      workspace: app.workspace,
                                                      note: "设备几何特征")
            message = "已写入并校验通过"
            app.log.ok("设备几何特征已写入：SubType=\(subtype) ProductType=\(productType)")
            refresh()
            Support.confirm(title: "需要注销才生效",
                            message: "SpringBoard 在启动时读取这些值。是否现在注销？",
                            destructive: "立即注销") {
                app.respring("设备几何特征")
            }
        } catch {
            message = "写入失败：\(error.localizedDescription)"
            app.log.fail(message)
        }
    }
}

struct DevicePreset: Identifiable {
    var id: String { productType }
    var name: String
    var productType: String
    var subtype: Int
}

enum DevicePresets {
    // SubType 是 SpringBoard 的屏幕几何档位，不是分辨率数值本身。
    // 这里只列社区已知可用的组合，未知档位一律不给。
    static let all: [DevicePreset] = [
        DevicePreset(name: "iPhone 16e（原生）", productType: "iPhone17,5", subtype: 4310),
        DevicePreset(name: "iPhone 16 Pro", productType: "iPhone17,1", subtype: 4312),
        DevicePreset(name: "iPhone 16 Pro Max", productType: "iPhone17,2", subtype: 4314),
        DevicePreset(name: "iPhone 17 Pro", productType: "iPhone18,1", subtype: 4340),
        DevicePreset(name: "iPhone 17 Pro Max", productType: "iPhone18,2", subtype: 4342)
    ]
}
