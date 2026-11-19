//
//  ProfileStore.swift
//  iOSTweaksToolbox
//
//  配置方案库。方案是本工具自己的 JSON 格式，与苹果系统原生配置路径无关。
//

import Foundation
import Combine

enum ProfileCategory: String, CaseIterable, Identifiable, Codable {
    case dynamicIsland = "DynamicIsland"
    case display = "Display"
    case aod = "AOD"
    case identity = "Identity"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamicIsland: return "灵动岛"
        case .display: return "显示"
        case .aod: return "AOD"
        case .identity: return "设备身份"
        }
    }
}

struct ProfileDocument: Identifiable, Codable {
    var id = UUID()
    var name: String
    var category: ProfileCategory
    var createdAt: Date
    var updatedAt: Date
    var payload: String          // JSON 文本，保持原样以便逐字节比较
    var note: String?

    var fileName: String { name.hasSuffix(".json") ? name : name + ".json" }
}

final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [ProfileDocument] = []

    private let workspace: WorkspacePaths
    private let fm = FileManager.default

    init(workspace: WorkspacePaths) { self.workspace = workspace }

    func directory(for category: ProfileCategory) -> URL {
        workspace.profiles.appendingPathComponent(category.rawValue, isDirectory: true)
    }

    func loadAll() {
        var list: [ProfileDocument] = []
        for category in ProfileCategory.allCases {
            let dir = directory(for: category)
            let urls = (try? fm.contentsOfDirectory(at: dir,
                                                    includingPropertiesForKeys: [.contentModificationDateKey],
                                                    options: [.skipsHiddenFiles])) ?? []
            for url in urls where url.pathExtension.lowercased() == "json" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let attributes = try? fm.attributesOfItem(atPath: url.path)
                let modified = attributes?[.modificationDate] as? Date ?? Date()
                list.append(ProfileDocument(name: url.deletingPathExtension().lastPathComponent,
                                            category: category,
                                            createdAt: attributes?[.creationDate] as? Date ?? modified,
                                            updatedAt: modified,
                                            payload: text,
                                            note: nil))
            }
        }
        profiles = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    func profiles(in category: ProfileCategory) -> [ProfileDocument] {
        profiles.filter { $0.category == category }
    }

    @discardableResult
    func save(_ profile: ProfileDocument) throws -> URL {
        let dir = directory(for: profile.category)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(profile.fileName)
        try profile.payload.write(to: url, atomically: true, encoding: .utf8)
        loadAll()
        return url
    }

    func delete(_ profile: ProfileDocument) throws {
        let url = directory(for: profile.category).appendingPathComponent(profile.fileName)
        try fm.removeItem(at: url)
        loadAll()
    }

    func importProfile(from url: URL, category: ProfileCategory) throws -> ProfileDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        // 校验是合法 JSON 才收进来
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw ToolboxError.parseFailed("不是合法 JSON")
        }
        let profile = ProfileDocument(name: url.deletingPathExtension().lastPathComponent,
                                      category: category,
                                      createdAt: Date(),
                                      updatedAt: Date(),
                                      payload: text,
                                      note: "导入自 \(url.lastPathComponent)")
        try save(profile)
        return profile
    }

    /// 首次启动写入内置方案。
    func seedIfEmpty() {
        loadAll()
        guard profiles.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for preset in IslandConfiguration.presets {
            if let data = try? encoder.encode(preset),
               let text = String(data: data, encoding: .utf8) {
                let name = preset.name.replacingOccurrences(of: " ", with: "-")
                try? save(ProfileDocument(name: name,
                                          category: .dynamicIsland,
                                          createdAt: Date(),
                                          updatedAt: Date(),
                                          payload: text,
                                          note: "内置预设"))
            }
        }

        let display = DisplayProfile(name: "Original", logicalWidth: 390, logicalHeight: 844, scale: 3.0)
        if let data = try? encoder.encode(display), let text = String(data: data, encoding: .utf8) {
            try? save(ProfileDocument(name: "Original", category: .display,
                                      createdAt: Date(), updatedAt: Date(),
                                      payload: text, note: "内置预设（模拟值）"))
        }

        let aodOff = AODProfileSnapshot(name: "AOD-Disabled", aodEnabled: false,
                                        systemVersion: OSCompatibility.systemVersion,
                                        build: OSCompatibility.build, note: "预设")
        let aodOn = AODProfileSnapshot(name: "AOD-Enabled", aodEnabled: true,
                                       systemVersion: OSCompatibility.systemVersion,
                                       build: OSCompatibility.build, note: "预设")
        for snapshot in [aodOff, aodOn] {
            if let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) {
                try? save(ProfileDocument(name: snapshot.name, category: .aod,
                                          createdAt: Date(), updatedAt: Date(),
                                          payload: text, note: "内置预设"))
            }
        }
        loadAll()
    }
}
