//
//  AODLabView.swift
//  iOSTweaksToolbox
//
//  AOD 行为诊断：记录、测试流程、配置差异与报告导出。
//

import SwiftUI

struct AODLabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section {
                Text("工具能记录的是 App 侧观察到的应用生命周期事件。系统级息屏、锁屏触摸事件在未越狱环境下不可获取——这些项目会明确标注为「不可采集」，不会用推测值填充。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("当前记录：AOD").font(.footnote)
                    Spacer()
                    Picker("", selection: Binding(get: { app.aod.aodObservedEnabled },
                                                  set: { app.aod.aodObservedEnabled = $0 })) {
                        Text("关闭").tag(false)
                        Text("开启").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                Button {
                    app.aod.captureSnapshot(name: app.aod.aodObservedEnabled ? "AOD-Enabled" : "AOD-Disabled")
                } label: {
                    Label("记录当前配置快照", systemImage: "camera.on.rectangle")
                }
            } header: {
                Text("配置状态")
            } footer: {
                Text("AOD 开关本身要在「设置 → 显示与亮度 → 全天候显示屏」手动操作。")
            }

            Section("诊断流程") {
                if let pending = app.aod.pendingTest {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("正在测试：\(pending.phase)")
                            .font(.footnote.weight(.semibold))
                        Text("锁屏后双击屏幕，然后回到本页记录结果。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("唤醒成功") { app.aod.markTest(woke: true) }
                                .buttonStyle(.borderedProminent)
                            Button("未唤醒") { app.aod.markTest(woke: false) }
                                .buttonStyle(.bordered)
                            Button("取消") { app.aod.cancelTest() }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Button("测试 A：AOD 关闭时双击") {
                        app.aod.aodObservedEnabled = false
                        app.aod.captureSnapshot(name: "Before-Test-A")
                        app.aod.beginTest(phase: "AOD 关闭")
                    }
                    Button("测试 B：AOD 开启时双击") {
                        app.aod.aodObservedEnabled = true
                        app.aod.captureSnapshot(name: "Before-Test-B")
                        app.aod.beginTest(phase: "AOD 开启")
                    }
                    Button("测试 C：对比可见配置目录") {
                        app.aod.compareBundledProfiles()
                    }
                }
            }

            if !app.aod.tests.isEmpty {
                Section("测试记录") {
                    ForEach(app.aod.tests) { test in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(test.phase).font(.footnote)
                                Text(test.startedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: test.woke == true ? "唤醒成功" : "未唤醒",
                                        tint: test.woke == true ? .green : .red)
                        }
                    }
                }
            }

            if !app.aod.differences.isEmpty {
                Section("配置差异") {
                    ForEach(app.aod.differences) { diff in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diff.file).font(.caption).foregroundStyle(.secondary)
                            Text(diff.outcome).font(.footnote)
                            ForEach(diff.changedKeys.prefix(20), id: \.self) { key in
                                Text(key).font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("不可采集项（未越狱）") {
                KeyValueRow(key: "系统息屏事件", value: "不可采集")
                KeyValueRow(key: "锁屏双击触摸事件", value: "不可采集")
                KeyValueRow(key: "AOD 亮度调度", value: "不可采集")
                KeyValueRow(key: "显示驱动电源状态", value: "不可采集")
            }

            Section("时间线（最近 60 条）") {
                ForEach(Array(app.aod.events.suffix(60)), id: \.id) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.date.formatted(date: .omitted, time: .standard))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.kind.rawValue).font(.caption)
                            if !event.detail.isEmpty {
                                Text(event.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    if let url = try? app.aod.exportReport() {
                        app.log.append(.success, "AOD 诊断报告已导出：\(url.path)")
                    }
                } label: {
                    Label("导出诊断报告", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("AOD 实验室")
        .onAppear { app.aod.startObserving() }
        .onDisappear { app.aod.stopObserving() }
    }
}
