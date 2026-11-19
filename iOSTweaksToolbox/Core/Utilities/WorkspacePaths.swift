//
//  WorkspacePaths.swift
//  iOSTweaksToolbox
//
//  所有可写数据的落点，全部位于 App 自己的沙盒内。
//

import Foundation

final class WorkspacePaths {
    let documents: URL
    let root: URL
    let profiles: URL
    let backups: URL
    let journals: URL
    let imports: URL
    let snapshots: URL

    init() {
        let fm = FileManager.default
        documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = documents.appendingPathComponent("TweaksToolbox", isDirectory: true)
        profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        backups = root.appendingPathComponent("Backups", isDirectory: true)
        journals = root.appendingPathComponent("Journals", isDirectory: true)
        imports = root.appendingPathComponent("Imports", isDirectory: true)
        snapshots = root.appendingPathComponent("Snapshots", isDirectory: true)
    }

    func prepare() {
        let fm = FileManager.default
        for url in [root, profiles, backups, journals, imports, snapshots] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for group in ["DynamicIsland", "Display", "AOD", "Identity", "Backups"] {
            try? fm.createDirectory(at: profiles.appendingPathComponent(group, isDirectory: true),
                                    withIntermediateDirectories: true)
        }
    }

    /// 自己 App Group 容器的根目录；没有 App Group 权限时为 nil。
    static func appGroupURL() -> URL? {
        guard let group = appGroupIdentifier() else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    /// 通过应用内登记的 group 名尝试；没有配置则返回 nil。
    static func appGroupIdentifier() -> String? {
        guard let list = Bundle.main.object(forInfoDictionaryKey: "AppGroups") as? [String],
              let first = list.first, !first.isEmpty else { return nil }
        return first
    }
}
