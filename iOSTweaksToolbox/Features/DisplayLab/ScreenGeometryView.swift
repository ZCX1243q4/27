//
//  ScreenGeometryView.swift
//  iOSTweaksToolbox
//
//  真实写入屏幕几何档位（ArtworkTraits.ArtworkDeviceSubType）。
//  这是未越狱环境下唯一能落地的显示几何改动。
//

import SwiftUI

struct ScreenGeometryView: View {
    @EnvironmentObject private var app: AppState

    @State private var current: Int?
    @State private var target = ""
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "当前 SubType", value: current.map(String.init) ?? "未读取")
            } header: {
                Text("系统当前值")
            }

            Section {
                ForEach(GeometryPresets.all) { preset in
                    Button {
                        target = String(preset.subtype)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.footnote)
                                Text("\(preset.logical) · \(preset.note)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(preset.subtype))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(current == preset.subtype ? Color.green : Color.primary)
                            if current == preset.subtype {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            } header: {
                Text("可选几何档位")
            } footer: {
                Text("档位取自系统已有的屏幕几何定义。切到目标档位后，SpringBoard 会按那个机型的屏幕形状布局。")
            }

            Section {
                HStack {
                    Text("自定义 SubType").font(.footnote)
                    Spacer()
                    TextField("整数", text: $target)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            } footer: {
                Text("写入系统不认识的档位会让布局崩坏，只建议在已知档位间切换。")
            }

            Section {
                Button {
                    write()
                } label: {
                    Label("写入系统缓存", systemImage: "square.and.arrow.down")
                }
                .disabled(busy || Int(target) == nil)
            } footer: {
                if message.isEmpty {
                    Text("原位覆盖 + F_FULLFSYNC + 读回校验 + inode/属主/权限校验，任一项异常自动回滚。写入后需重启设备生效。")
                } else {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("屏幕几何档位")
        .onAppear {
            _ = WorseQuery.shared.grant(MGPath.systemGestalt)
            let profile = GestaltService.readDeviceProfile()
            current = profile.subtype
            target = profile.subtype.map(String.init) ?? ""
        }
    }

    private func write() {
        guard let value = Int(target) else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try GestaltService.applyDeviceProfile(subtype: value,
                                                      deviceName: nil,
                                                      productType: nil,
                                                      workspace: app.workspace,
                                                      note: "屏幕几何档位")
            current = value
            message = "已写入 SubType = \(value)"
            app.log.ok("屏幕几何档位已写入：\(value)")
        } catch {
            message = "写入失败：\(error.localizedDescription)"
            app.log.fail(message)
        }
    }
}
struct GeometryPreset: Identifiable {
    var id: Int { subtype }
    var subtype: Int
    var name: String
    var logical: String
    var note: String
}

enum GeometryPresets {
    static let all: [GeometryPreset] = [
        GeometryPreset(subtype: 2436, name: "iPhone X / 11 Pro 几何",
                       logical: "375×812 @3x", note: "刘海，5.8寸"),
        GeometryPreset(subtype: 2532, name: "iPhone 12/13/14 几何",
                       logical: "390×844 @3x", note: "刘海，6.1寸"),
        GeometryPreset(subtype: 2340, name: "iPhone 12 mini 几何",
                       logical: "375×812 @3x", note: "刘海，5.4寸"),
        GeometryPreset(subtype: 2778, name: "iPhone 12/13 Pro Max 几何",
                       logical: "428×926 @3x", note: "刘海，6.7寸"),
        GeometryPreset(subtype: 2556, name: "iPhone 14 Pro / 15 / 16 几何",
                       logical: "393×852 @3x", note: "灵动岛，6.1寸"),
        GeometryPreset(subtype: 2796, name: "iPhone 15 Pro Max 几何",
                       logical: "430×932 @3x", note: "灵动岛，6.7寸"),
        GeometryPreset(subtype: 2622, name: "iPhone 16 Pro 几何",
                       logical: "402×874 @3x", note: "灵动岛，6.3寸"),
        GeometryPreset(subtype: 2868, name: "iPhone 16 Pro Max 几何",
                       logical: "440×956 @3x", note: "灵动岛，6.9寸")
    ]
}
