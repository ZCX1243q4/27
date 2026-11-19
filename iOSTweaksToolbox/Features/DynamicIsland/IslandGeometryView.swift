//
//  IslandGeometryView.swift
//  iOSTweaksToolbox
//
//  灵动岛纵向位置与屏幕几何的真实杠杆：ArtworkTraits.SubType。
//  SubType 是系统的屏幕几何档位，切换档位会改变灵动岛在状态栏里的纵向位置。
//

import SwiftUI

struct IslandGeometryView: View {
    @EnvironmentObject private var app: AppState

    @State private var currentSubtype: Int?
    @State private var target = ""
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "当前 SubType", value: currentSubtype.map(String.init) ?? "不存在")
            } header: {
                Text("系统当前值")
            }

            Section {
                ForEach(IslandGeometry.options) { option in
                    Button {
                        target = String(option.subtype)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).font(.footnote)
                                Text(option.note).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(option.subtype))
                                .font(.system(.caption, design: .monospaced))
                            if currentSubtype == option.subtype {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if target == String(option.subtype) {
                                Image(systemName: "circle.inset.filled").foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("可选几何档位")
            } footer: {
                Text("档位来自系统已有的屏幕几何定义。切到更高档位的机型几何，灵动岛会下移到对应位置。")
            }

            Section {
                HStack {
                    Text("自定义 SubType").font(.footnote)
                    Spacer()
                    TextField("整数", text: $target)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
            }

            Section {
                Button {
                    write()
                } label: {
                    Label("写入并注销生效", systemImage: "square.and.arrow.down")
                }
                .disabled(busy || Int(target) == nil)
            } footer: {
                if message.isEmpty {
                    Text("写入 ArtworkTraits.SubType，原位覆盖 + 读回校验 + 失败回滚。")
                } else {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("灵动岛几何档位")
        .onAppear {
            _ = WorseQuery.shared.grant(MGPath.systemGestalt)
            let profile = GestaltService.readDeviceProfile()
            currentSubtype = profile.subtype
            target = profile.subtype.map(String.init) ?? ""
        }
    }

    private func write() {
        guard let subtype = Int(target) else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try GestaltService.applyDeviceProfile(subtype: subtype,
                                                      deviceName: nil,
                                                      productType: nil,
                                                      workspace: app.workspace,
                                                      note: "灵动岛几何")
            currentSubtype = subtype
            message = "已写入 SubType = \(subtype)"
            app.log.ok("灵动岛几何 SubType 已写入：\(subtype)")
            app.respring("灵动岛几何档位")
        } catch {
            message = "写入失败：\(error.localizedDescription)"
            app.log.fail(message)
        }
    }
}

struct IslandGeometryOption: Identifiable {
    var id: Int { subtype }
    var subtype: Int
    var name: String
    var note: String
}

enum IslandGeometry {
    // SubType 是系统的屏幕几何档位。数值来自社区对 ArtworkTraits 的整理，
    // 只在已知档位之间提供切换，避免写入系统不认识的几何导致布局崩坏。
    static let options: [IslandGeometryOption] = [
        IslandGeometryOption(subtype: 2436, name: "iPhone X / 11 Pro 几何", note: "426×852 @3x，刘海"),
        IslandGeometryOption(subtype: 2532, name: "iPhone 12 / 13 / 14 几何", note: "390×844 @3x，刘海"),
        IslandGeometryOption(subtype: 2556, name: "iPhone 14 Pro / 15 / 16 几何", note: "393×852 @3x，灵动岛"),
        IslandGeometryOption(subtype: 2796, name: "iPhone 15 Pro Max 几何", note: "430×932 @3x，灵动岛"),
        IslandGeometryOption(subtype: 2622, name: "iPhone 16 Pro 几何", note: "402×874 @3x，灵动岛"),
        IslandGeometryOption(subtype: 2868, name: "iPhone 16 Pro Max 几何", note: "440×956 @3x，灵动岛")
    ]
}
