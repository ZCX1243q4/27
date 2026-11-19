//
//  DisplayLabView.swift
//  iOSTweaksToolbox
//
//  显示参数：真实读取 + 真实写入 ArtworkTraits。
//  这里没有模拟滑杆——改不了的东西就不做滑块。
//

import SwiftUI

struct DisplayLabView: View {
    @EnvironmentObject private var app: AppState

    @State private var snapshot: DisplaySnapshot?
    @State private var subtype: Int?
    @State private var deviceName = ""
    @State private var productType = ""

    var body: some View {
        List {
            if let snapshot {
                Section("真实显示参数（公开 API 读取）") {
                    HStack(spacing: 8) {
                        StatTile(title: "逻辑尺寸",
                                 value: "\(Int(snapshot.boundsWidth))×\(Int(snapshot.boundsHeight))")
                        StatTile(title: "原生像素",
                                 value: "\(Int(snapshot.nativeBoundsWidth))×\(Int(snapshot.nativeBoundsHeight))")
                        StatTile(title: "Scale", value: String(format: "%.1f", snapshot.scale))
                    }
                    KeyValueRow(key: "Native Scale", value: String(format: "%.3f", snapshot.nativeScale))
                    KeyValueRow(key: "设备标识", value: snapshot.deviceModel, mono: true)
                    KeyValueRow(key: "系统", value: "\(snapshot.systemVersion) (\(snapshot.buildNumber))")
                    KeyValueRow(key: "安全区", value: "顶部 \(Int(snapshot.safeAreaTop)) / 底部 \(Int(snapshot.safeAreaBottom))")
                }
            }

            Section {
                KeyValueRow(key: "ArtworkDeviceSubType", value: subtype.map(String.init) ?? "未读取")
                KeyValueRow(key: "设备产品名", value: deviceName.isEmpty ? "—" : deviceName)
                KeyValueRow(key: "ProductType", value: productType.isEmpty ? "—" : productType, mono: true)
            } header: {
                Text("系统缓存里的几何特征")
            } footer: {
                Text("这三项来自 MobileGestalt 的 CacheExtra。SubType 是 SpringBoard 选择屏幕几何与设备图形特征的档位。")
            }

            Section {
                NavigationLink {
                    ResolutionChangerView()
                } label: {
                    Label("修改全局分辨率（真实写入）", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            } footer: {
                Text("写 IOMobileGraphicsFamily 的画布尺寸，这是 iOS 显示服务启动时读取的值。重启后生效。")
            }

            Section {
                NavigationLink {
                    ScreenGeometryView()
                } label: {
                    Label("修改屏幕几何档位", systemImage: "rectangle.inset.filled")
                }
            } footer: {
                Text("改 ArtworkTraits 的 SubType，影响系统对屏幕形状的判断。")
            }

            Section {
                Text("""
                关于「全局修改分辨率」：

                iOS 的逻辑分辨率 = 硬件像素 ÷ scale，三者由设备树和显示驱动在启动时确定，运行期没有可写入口。IOMobileFramebuffer 的 SetDisplayMode 需要 platform-application 级别的签名权限，普通开发者证书拿不到，越狱也只是把这条路打开而不是绕过硬件。

                所以任何号称能改全局分辨率的未越狱 App，实际能改的只有 ArtworkTraits 里的几何档位——它影响系统对屏幕形状的判断（比如灵动岛的位置、圆角资源），但不会让 1170×2532 的屏幕变成别的数字。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("显示参数")
        .onAppear { load() }
    }

    private func load() {
        snapshot = DisplayService.snapshot()
        _ = WorseQuery.shared.grant(MGPath.systemGestalt)
        let profile = GestaltService.readDeviceProfile()
        subtype = profile.subtype
        deviceName = profile.deviceName
        productType = profile.productType
    }
}
