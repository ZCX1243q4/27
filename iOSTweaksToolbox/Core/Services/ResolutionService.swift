//
//  ResolutionService.swift
//  iOSTweaksToolbox
//
//  真正的分辨率修改：写 IOMobileGraphicsFamily 的 canvas_width / canvas_height。
//  这是 iOS 显示服务在启动时读取的绘图画布尺寸，不是 MobileGestalt。
//
//  来源：Nugget 的 RdarFixTweak（src/tweaks/tweak_classes.py）+ FileLocation.resolution
//  （src/tweaks/basic_plist_locations.py）。
//

import Foundation

enum ResolutionPath {
    /// 显示服务读取的画布配置。改这个才是真改分辨率。
    static let graphicsFamily = "/var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist"
    /// 目录本身，用来给 worse_query 申请令牌。
    static let graphicsDirectory = "/var/Managed Preferences/mobile"
}

struct CanvasConfig {
    var width: Int
    var height: Int
    var exists: Bool
    var readable: Bool
    var writable: Bool
    var raw: [String: Any]
}

struct ResolutionPreset: Identifiable {
    var id: String { "\(width)x\(height)" }
    var name: String
    var width: Int
    var height: Int
    var note: String
}

enum ResolutionService {
    /// 已知机型画布尺寸。canvas 是物理像素，不是逻辑点。
    static let presets: [ResolutionPreset] = [
        ResolutionPreset(name: "iPhone 16e（原生）", width: 1170, height: 2532, note: "390×844 @3x"),
        ResolutionPreset(name: "iPhone 12/13/14", width: 1170, height: 2532, note: "390×844 @3x"),
        ResolutionPreset(name: "iPhone 12/13 mini", width: 1080, height: 2340, note: "375×812 @3x"),
        ResolutionPreset(name: "iPhone 14/15/16", width: 1179, height: 2556, note: "393×852 @3x"),
        ResolutionPreset(name: "iPhone 16 Pro", width: 1206, height: 2622, note: "402×874 @3x"),
        ResolutionPreset(name: "iPhone 15 Pro Max", width: 1290, height: 2796, note: "430×932 @3x"),
        ResolutionPreset(name: "iPhone 16 Pro Max", width: 1320, height: 2868, note: "440×956 @3x"),
        ResolutionPreset(name: "iPhone X / 11 Pro", width: 1125, height: 2436, note: "375×812 @3x"),
        ResolutionPreset(name: "iPhone XR / 11", width: 828, height: 1791, note: "414×896 @2x"),
        ResolutionPreset(name: "iPhone SE 2/3", width: 750, height: 1334, note: "375×667 @2x")
    ]

    // MARK: - 读取

    static func readCanvas() -> CanvasConfig? {
        let url = URL(fileURLWithPath: ResolutionPath.graphicsFamily)
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)

        guard exists else {
            return CanvasConfig(width: 0, height: 0,
                                exists: false,
                                readable: false,
                                writable: false,
                                raw: [:])
        }
        guard let data = try? Data(contentsOf: url),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return CanvasConfig(width: 0, height: 0,
                                exists: true,
                                readable: false,
                                writable: fm.isWritableFile(atPath: url.path),
                                raw: [:])
        }
        let width = (dict["canvas_width"] as? NSNumber)?.intValue ?? 0
        let height = (dict["canvas_height"] as? NSNumber)?.intValue ?? 0
        return CanvasConfig(width: width, height: height,
                            exists: true,
                            readable: true,
                            writable: fm.isWritableFile(atPath: url.path),
                            raw: dict)
    }

    // MARK: - 写入

    /// 写入画布尺寸。保留文件里其他键，只改这两个。
    @discardableResult
    static func writeCanvas(width: Int, height: Int, workspace: WorkspacePaths) throws -> Data {
        guard width >= 640, width <= 3000, height >= 960, height <= 3400 else {
            throw ToolboxError.parseFailed("画布尺寸超出安全范围（宽 640–3000，高 960–3400）")
        }
        let url = URL(fileURLWithPath: ResolutionPath.graphicsFamily)
        let fm = FileManager.default

        var dict: [String: Any] = [:]
        var before: Data?

        if fm.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url) else {
                throw ToolboxError.parseFailed("文件存在但读取失败，已中止写入")
            }
            before = data
            dict = ((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]) ?? [:]
        }

        dict["canvas_width"] = width
        dict["canvas_height"] = height

        let output = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)

        // 快照，便于回滚
        if let before {
            let dir = workspace.root.appendingPathComponent("Resolution", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? before.write(to: dir.appendingPathComponent("before-\(EventLog.stamp()).plist"), options: .atomic)
        }

        if fm.fileExists(atPath: url.path) {
            try GestaltService.writeInPlace(output, to: url)
        } else {
            // 文件不存在时要先确认目录可写
            let dir = URL(fileURLWithPath: ResolutionPath.graphicsDirectory)
            guard fm.isWritableFile(atPath: dir.path) else {
                throw ToolboxError.notWritable("目录不可写：\(dir.path)")
            }
            try output.write(to: url, options: .atomic)
        }
        return before ?? Data()
    }

    /// 为这个路径申请 worse_query 令牌。
    static func requestAccess() -> (ok: Bool, message: String) {
        let direct = WorseQuery.shared.grant(ResolutionPath.graphicsFamily)
        if direct.ok { return (true, direct.message) }
        let dir = WorseQuery.shared.grant(ResolutionPath.graphicsDirectory)
        if dir.ok { return (true, dir.message) }
        return (false, direct.message + " / " + dir.message)
    }
}
