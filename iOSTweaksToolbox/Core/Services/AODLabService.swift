//
//  AODLabService.swift
//  iOSTweaksToolbox
//
//  AOD 行为记录与开关前后配置差异。所有观察都来自本 App 能收到的
//  应用生命周期通知；拿不到系统级息屏事件时不伪造记录。
//

import Foundation
import Combine
import UIKit

struct AODProfileSnapshot: Codable, Identifiable {
    var id = UUID()
    var name: String
    var aodEnabled: Bool
    var systemVersion: String
    var build: String
    var createdAt: Date = Date()
    var note: String = ""
}

enum AODEventKind: String, Codable {
    case didBecomeActive = "App 进入前台"
    case willResignActive = "App 失去前台"
    case didEnterBackground = "App 进入后台"
    case willEnterForeground = "App 即将回到前台"
    case protectedDataAvailable = "受保护数据可用"
    case protectedDataUnavailable = "受保护数据不可用"
    case batteryStateChanged = "电池状态变化"
    case userMarked = "用户标记"
}

struct AODEvent: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var kind: AODEventKind
    var detail: String
}

struct AODTestResult: Identifiable, Codable {
    var id = UUID()
    var phase: String            // "AOD 关闭" / "AOD 开启"
    var startedAt: Date
    var finishedAt: Date?
    var woke: Bool?
    var note: String = ""
}

struct AODDifference: Identifiable, Codable {
    var id = UUID()
    var file: String
    var outcome: String
    var changedKeys: [String] = []
}

struct AODDiagnosticReport: Codable {
    var generatedAt = Date()
    var systemVersion: String
    var build: String
    var device: String
    var events: [AODEvent]
    var tests: [AODTestResult]
    var differences: [AODDifference]
    var notes: [String]
}

@MainActor
final class AODLabService: ObservableObject {
    @Published private(set) var events: [AODEvent] = []
    @Published private(set) var tests: [AODTestResult] = []
    @Published private(set) var differences: [AODDifference] = []
    @Published private(set) var snapshots: [AODProfileSnapshot] = []
    @Published var aodObservedEnabled: Bool = false
    @Published var pendingTest: AODTestResult?

    private let workspace: WorkspacePaths
    private var observers: [NSObjectProtocol] = []

    init(workspace: WorkspacePaths) { self.workspace = workspace }

    // MARK: - 生命周期

    func load() {
        loadEvents()
        loadSnapshots()
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [(Notification.Name, AODEventKind)] = [
            (UIApplication.didBecomeActiveNotification, .didBecomeActive),
            (UIApplication.willResignActiveNotification, .willResignActive),
            (UIApplication.didEnterBackgroundNotification, .didEnterBackground),
            (UIApplication.willEnterForegroundNotification, .willEnterForeground),
            (UIApplication.protectedDataDidBecomeAvailableNotification, .protectedDataAvailable),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, .protectedDataUnavailable)
        ]
        for (name, kind) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.record(kind, detail: "") }
            }
            observers.append(token)
        }
    }

    func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func record(_ kind: AODEventKind, detail: String) {
        let event = AODEvent(kind: kind, detail: detail)
        events.append(event)
        persistEvents()
    }

    // MARK: - 测试流程

    func beginTest(phase: String) {
        let result = AODTestResult(phase: phase, startedAt: Date(), finishedAt: nil, woke: nil)
        pendingTest = result
        record(.userMarked, detail: "开始测试：\(phase)")
    }

    func markTest(woke: Bool) {
        guard var result = pendingTest else { return }
        result.finishedAt = Date()
        result.woke = woke
        tests.append(result)
        pendingTest = nil
        record(.userMarked, detail: "测试结论：\(result.phase) → \(woke ? "唤醒成功" : "未唤醒")")
    }

    func cancelTest() {
        pendingTest = nil
        record(.userMarked, detail: "已取消当前测试")
    }

    /// 记录当前配置快照，用于开关 AOD 前后对比。
    func captureSnapshot(name: String) {
        let snapshot = AODProfileSnapshot(name: name,
                                          aodEnabled: aodObservedEnabled,
                                          systemVersion: OSCompatibility.systemVersion,
                                          build: OSCompatibility.build)
        snapshots.append(snapshot)
        try? saveSnapshots()

        // 同时对工具自身可见的配置目录做一次文件级快照，并两两比对
        let folder = workspace.profiles.appendingPathComponent("AOD", isDirectory: true)
        let snapshotFolder = workspace.snapshots.appendingPathComponent("AOD-\(EventLog.stamp())", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.copyItem(at: file, to: snapshotFolder.appendingPathComponent(file.lastPathComponent))
        }
        record(.userMarked, detail: "已记录 AOD 配置快照：\(name)")
    }

    /// 比较工具可见目录下的两份 JSON 配置，只报告差异，不改动任何字段。
    func compareBundledProfiles() {
        let folder = workspace.profiles.appendingPathComponent("AOD", isDirectory: true)
        let all = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                includingPropertiesForKeys: nil)) ?? []
        let files = all
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.count >= 2 else {
            differences = []
            return
        }
        var result: [AODDifference] = []
        for i in 0..<(files.count - 1) {
            for j in (i + 1)..<files.count {
                let dataA = (try? Data(contentsOf: files[i])) ?? Data()
                let dataB = (try? Data(contentsOf: files[j])) ?? Data()
                guard let a = (try? JSONSerialization.jsonObject(with: dataA)) as? [String: Any],
                      let b = (try? JSONSerialization.jsonObject(with: dataB)) as? [String: Any] else {
                    result.append(AODDifference(file: "\(files[i].lastPathComponent) ↔ \(files[j].lastPathComponent)",
                                                outcome: "无法解析"))
                    continue
                }
                let changed = DiffEngine.diff(old: a, new: b).map { "\($0.path) [\($0.kind.rawValue)]" }
                result.append(AODDifference(file: "\(files[i].lastPathComponent) ↔ \(files[j].lastPathComponent)",
                                            outcome: changed.isEmpty ? "无差异" : "\(changed.count) 处差异",
                                            changedKeys: changed))
            }
        }
        differences = result
    }

    func report() -> AODDiagnosticReport {
        AODDiagnosticReport(systemVersion: OSCompatibility.systemVersion,
                            build: OSCompatibility.build,
                            device: DeviceInfoService.hardwareIdentifier(),
                            events: events,
                            tests: tests,
                            differences: differences,
                            notes: [
                                "本报告只描述 App 能观察到的应用生命周期事件。",
                                "系统级息屏与锁屏触摸事件未越狱无法获取，报告不会伪造这类记录。",
                                "AOD 开关本身需要在「设置 → 显示与亮度」中手动操作。"
                            ])
    }

    func exportReport() throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = workspace.journals.appendingPathComponent("AOD-diagnostic-\(EventLog.stamp()).json")
        try encoder.encode(report()).write(to: url, options: .atomic)
        return url
    }

    // MARK: - 持久化

    private var eventsURL: URL { workspace.journals.appendingPathComponent("AOD-events.json") }
    private var snapshotsURL: URL { workspace.journals.appendingPathComponent("AOD-snapshots.json") }

    private func loadEvents() {
        guard let data = try? Data(contentsOf: eventsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        events = (try? decoder.decode([AODEvent].self, from: data)) ?? []
    }

    private func persistEvents() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(events).write(to: eventsURL, options: .atomic)
    }

    private func loadSnapshots() {
        guard let data = try? Data(contentsOf: snapshotsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshots = (try? decoder.decode([AODProfileSnapshot].self, from: data)) ?? []
    }

    private func saveSnapshots() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshots).write(to: snapshotsURL, options: .atomic)
    }
}
