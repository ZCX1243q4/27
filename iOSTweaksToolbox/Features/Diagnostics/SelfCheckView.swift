//
//  SelfCheckView.swift
//  iOSTweaksToolbox
//
//  逐项真机自检。每一项都给出真实返回值，不猜、不糊。
//

import SwiftUI

struct SelfCheckView: View {
    @EnvironmentObject private var app: AppState

    @State private var rows: [CheckRow] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                Button {
                    run()
                } label: {
                    Label(running ? "检测中…" : "开始自检", systemImage: "stethoscope")
                }
                .disabled(running)
            } footer: {
                Text("这一页直接跑真实调用并把返回码原样显示。哪一步断了，后面所有写入都不可能成功。")
            }

            Section("结果") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.title).font(.footnote.weight(.medium))
                            Spacer()
                            StatusBadge(text: row.ok ? "通过" : "失败", tint: row.ok ? .green : .red)
                        }
                        Text(row.detail)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("真机自检")
        .onAppear { if rows.isEmpty { run() } }
    }

    private func run() {
        running = true
        rows = []
        var result: [CheckRow] = []

        // 1. Bundle ID
        result.append(CheckRow(title: "Bundle ID",
                               ok: true,
                               detail: Bundle.main.bundleIdentifier ?? "未知"))

        // 2. 签名里的 App Group
        let groups = SelfCheck.signedAppGroups()
        result.append(CheckRow(title: "签名 entitlements 里的 App Group",
                               ok: !groups.isEmpty,
                               detail: groups.isEmpty
                                    ? "空。重签工具没有给你 com.apple.security.application-groups，worse_query 无法工作"
                                    : groups.joined(separator: ", ")))

        // 3. NSFileManager 能否打开 group 容器
        var containerOK = false
        for group in groups {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                containerOK = true
                result.append(CheckRow(title: "App Group 容器可打开",
                                       ok: true,
                                       detail: url.path))
                break
            }
        }
        if !containerOK {
            result.append(CheckRow(title: "App Group 容器可打开",
                                   ok: false,
                                   detail: "一个都打不开。签名者注入了 entitlement 但没有真正分配容器"))
        }

        // 4. 系统文件当前可见性（未拿令牌时的基线）
        let path = MGPath.systemGestalt
        let readableBefore = FileManager.default.isReadableFile(atPath: path)
        result.append(CheckRow(title: "系统 MobileGestalt（未取令牌时）",
                               ok: !readableBefore,
                               detail: readableBefore
                                    ? "居然可读——说明这个 App 本身权限异常"
                                    : "不可读，符合预期（需要令牌）"))

        // 5. worse_query 拿令牌
        let grant = WorseQuery.shared.grant(path)
        result.append(CheckRow(title: "worse_query 取令牌",
                               ok: grant.ok,
                               detail: "返回句柄 \(grant.handle)；\(grant.message)"))

        // 6. 令牌生效后能否读
        let readableAfter = FileManager.default.isReadableFile(atPath: path)
        let data = (try? Data(contentsOf: URL(fileURLWithPath: path)))
        result.append(CheckRow(title: "令牌生效后可读系统文件",
                               ok: readableAfter && (data?.count ?? 0) > 0,
                               detail: readableAfter
                                    ? "读取到 \(data?.count ?? 0) 字节"
                                    : "仍不可读，令牌没有覆盖到这个路径"))

        // 7. 能否解析
        if let data, let dict = GestaltService.parse(data) {
            let extra = dict["CacheExtra"] as? [String: Any]
            result.append(CheckRow(title: "解析 plist",
                                   ok: true,
                                   detail: "根字典 \(dict.count) 项，CacheExtra \(extra?.count ?? 0) 项"))
        } else {
            result.append(CheckRow(title: "解析 plist", ok: false, detail: "解析失败"))
        }

        // 8. 可写性
        result.append(CheckRow(title: "系统文件可写",
                               ok: FileManager.default.isWritableFile(atPath: path),
                               detail: FileManager.default.isWritableFile(atPath: path)
                                    ? "可写"
                                    : "不可写（多数情况是 App Group 没生效）"))

        // 9. OS 版本窗口
        result.append(CheckRow(title: "系统版本窗口",
                               ok: !OSCompatibility.isPatchedBuild,
                               detail: "iOS \(OSCompatibility.systemVersion) (\(OSCompatibility.build))"
                                    + (OSCompatibility.isPatchedBuild ? " —— 已被 Apple 修复" : "")))

        rows = result
        running = false
        for row in result {
            app.log.append(row.ok ? .success : .error, "[自检] \(row.title)：\(row.detail)")
        }
    }
}

struct CheckRow: Identifiable {
    var id = UUID()
    var title: String
    var ok: Bool
    var detail: String
}

enum SelfCheck {
    static func signedAppGroups() -> [String] {
        if let task = SecTaskCreateFromSelf(nil),
           let value = SecTaskCopyValueForEntitlement(task,
                                                      "com.apple.security.application-groups" as CFString,
                                                      nil),
           let groups = value as? [String] {
            return groups
        }
        return (Bundle.main.object(forInfoDictionaryKey: "AppGroups") as? [String]) ?? []
    }
}
