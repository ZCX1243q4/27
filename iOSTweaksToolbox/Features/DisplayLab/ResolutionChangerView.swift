//
//  ResolutionChangerView.swift
//  iOSTweaksToolbox
//
//  真正的全局分辨率修改。写的是 IOMobileGraphicsFamily 的画布尺寸，
//  不是 MobileGestalt，也不是 App 内模拟。
//

import SwiftUI

struct ResolutionChangerView: View {
    @EnvironmentObject private var app: AppState

    @State private var canvas: CanvasConfig?
    @State private var width = ""
    @State private var height = ""
    @State private var busy = false
    @State private var message = ""
    @State private var accessMessage = ""

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "配置文件", value: ResolutionPath.graphicsFamily, mono: true)
                if let canvas {
                    KeyValueRow(key: "文件存在", value: canvas.exists ? "是" : "否")
                    KeyValueRow(key: "可读", value: canvas.readable ? "是" : "否")
                    KeyValueRow(key: "可写", value: canvas.writable ? "是" : "否")
                    if canvas.exists {
                        KeyValueRow(key: "当前画布",
                                    value: canvas.width > 0 ? "\(canvas.width) × \(canvas.height)" : "未设置")
                    }
                } else {
                    KeyValueRow(key: "状态", value: "未读取")
                }
                if !accessMessage.isEmpty {
                    KeyValueRow(key: "令牌", value: accessMessage)
                }
            } header: {
                Text("系统当前值")
            } footer: {
                Text("这是 iOS 显示服务在启动时读取的绘图画布尺寸。改它才是改真正的全局分辨率——不是 MobileGestalt，也不是模拟。")
            }

            Section {
                Button {
                    grantAndRead()
                } label: {
                    Label("申请访问并读取", systemImage: "key.horizontal")
                }
            }

            Section {
                ForEach(ResolutionService.presets) { preset in
                    Button {
                        width = String(preset.width)
                        height = String(preset.height)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.footnote)
                                Text(preset.note).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(preset.width)×\(preset.height)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("机型画布参考")
            }

            Section {
                HStack {
                    Text("宽").font(.footnote)
                    Spacer()
                    TextField("px", text: $width)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
                HStack {
                    Text("高").font(.footnote)
                    Spacer()
                    TextField("px", text: $height)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
            } header: {
                Text("自定义画布")
            } footer: {
                Text("必须是物理像素。填成逻辑点（比如 390×844）会让界面变得极小。")
            }

            Section {
                Button {
                    apply()
                } label: {
                    Label("写入并重启生效", systemImage: "square.and.arrow.down")
                }
                .disabled(busy || Int(width) == nil || Int(height) == nil)
            } footer: {
                if message.isEmpty {
                    Text("写入后必须重启设备。画布尺寸在显示服务启动时读取，注销不够。不匹配的宽高比会让界面横向或纵向拉伸。")
                } else {
                    Text(message).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("""
                为什么之前改不动：

                分辨率不在 MobileGestalt 里。Nugget 的实现走的是 /var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist，只写 canvas_width 和 canvas_height 两个键（见 RdarFixTweak）。

                这个路径同样不在 App 沙盒里，所以还是要先拿 worse_query 令牌。拿到之后原位改写，重启生效。

                注意 iOS 26 起 Nugget 把这个功能隐藏了（v6.2.3 "Hid ... resolution changer on iOS 26.0"），原因是走它那套 restore 方法在 26 上失效。但我们用的是 worse_query 直接写文件，不吃 restore 那条路——能不能成，取决于令牌能不能覆盖到这个目录。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("全局分辨率")
        .onAppear { grantAndRead() }
    }

    private func grantAndRead() {
        let access = ResolutionService.requestAccess()
        accessMessage = access.message
        app.log.append(access.ok ? .success : .warning, "分辨率文件访问：\(access.message)")
        canvas = ResolutionService.readCanvas()
        if let canvas, canvas.width > 0 {
            width = String(canvas.width)
            height = String(canvas.height)
        }
    }

    private func apply() {
        guard let w = Int(width), let h = Int(height) else { return }
        busy = true
        defer { busy = false }
        do {
            let before = try ResolutionService.writeCanvas(width: w, height: h, workspace: app.workspace)
            message = "已写入 \(w) × \(h)" + (before.isEmpty ? "（新建文件）" : "（已保存原文件快照）")
            app.log.ok("分辨率已写入：\(w)×\(h)")
            canvas = ResolutionService.readCanvas()
        } catch {
            message = "写入失败：\(error.localizedDescription)"
            app.log.fail(message)
        }
    }
}
