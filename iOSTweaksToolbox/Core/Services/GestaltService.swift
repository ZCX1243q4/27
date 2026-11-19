//
//  GestaltService.swift
//  iOSTweaksToolbox
//
//  MobileGestalt 缓存的读取、备份与安全写入。
//  写入协议：pwrite 原位覆盖 + 尾部按需截断 + F_FULLFSYNC + 读回校验 + 失败回滚。
//

import Foundation
import Darwin

enum MGPath {
    static let systemGestalt = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static let savedOriginal = "OriginalGestalt.plist"
    static let savedDigest = "OriginalGestalt.sha256"
    static let preApply = "PreApplyGestalt.plist"
}

struct GestaltSnapshot {
    var url: URL
    var data: Data
    var size: Int
    var sha256: String
    var readable: Bool
    var writable: Bool
}

enum GestaltService {
    static func containerDirectory(_ workspace: WorkspacePaths) -> URL {
        workspace.root.appendingPathComponent("Gestalt", isDirectory: true)
    }

    static func fileURL(_ workspace: WorkspacePaths, _ name: String) -> URL {
        containerDirectory(workspace).appendingPathComponent(name)
    }

    // MARK: - 读取

    static func readSystem() -> GestaltSnapshot? {
        let url = URL(fileURLWithPath: MGPath.systemGestalt)
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: url) else { return nil }
        return GestaltSnapshot(url: url,
                               data: data,
                               size: data.count,
                               sha256: Hashing.sha256(data),
                               readable: fm.isReadableFile(atPath: url.path),
                               writable: fm.isWritableFile(atPath: url.path))
    }

    static func parse(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    // MARK: - 备份

    @discardableResult
    static func saveOriginal(_ data: Data, workspace: WorkspacePaths) throws -> String {
        let dir = containerDirectory(workspace)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = fileURL(workspace, MGPath.savedOriginal)
        try data.write(to: file, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = file
        try? mutable.setResourceValues(values)
        let digest = Hashing.sha256(data)
        try Data(digest.utf8).write(to: fileURL(workspace, MGPath.savedDigest), options: .atomic)
        return digest
    }

    static func loadOriginal(workspace: WorkspacePaths) -> (data: Data, digest: String, digestOK: Bool)? {
        let file = fileURL(workspace, MGPath.savedOriginal)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let actual = Hashing.sha256(data)
        let saved = (try? String(contentsOf: fileURL(workspace, MGPath.savedDigest), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = (saved?.caseInsensitiveCompare(actual) == .orderedSame)
        return (data, actual, ok)
    }

    // MARK: - 写入

    /// 明确禁止写入的键。这些是社区实测会导致开机缓存重置、
    /// 基带/Wi-Fi 死锁或软砖的项，任何一个都不放过。
    static let blockedKeys: [String: String] = [
        "zHeENZu+wbg7PUprwNwBWg": "RegionInfo —— iOS 27 上的非缓存键，注入会触发开机缓存合法性校验整包重置",
        "0L5PkT61qoH1b/B1USWqjQ": "RegionalBehaviorChinaBrick —— 非缓存硬件键，写入会导致开机重置",
        "gD8SNRcHQeIxCAvsp+2vjA": "WSKU —— 无线电射频校准数据，篡改可致 Wi-Fi/蓝牙瘫痪",
        "sFTm4FEVKVfdZ0ChdwQY1g": "WifiAntennaSKUVersion —— 天线校准参数",
        "91LyMcx4z1w3SGVeqteMnA": "BasebandRegionSKU —— 基带射频参数，篡改可致基带死锁",
        "iyfxmLogGVIaH7aEgqwcIA": "green-tea —— 属于 CacheData 二进制槽位，不能塞进 CacheExtra",
        "4snMZS8LJkSctKypt2m+xA": "not-green-tea —— 属于 CacheData 二进制槽位",
        "hiHut/WR+B9Lx/vd0WyeNg": "wapi —— 属于 CacheData 二进制槽位",
        "green-tea": "green-tea —— 明文冲突键",
        "not-green-tea": "not-green-tea —— 明文冲突键",
        "wapi": "wapi —— 明文冲突键",
        "uKc7FPnEO++lVhHWHFlGbQ": "iPad 设备模式 —— 与台前调度叠加会导致白苹果循环",
        "CacheData": "顶层系统保留字段",
        "CacheUUID": "顶层系统保留字段",
        "CacheVersion": "顶层系统保留字段"
    ]

    static func blockedReason(for key: String) -> String? { blockedKeys[key] }

    enum WriteError: LocalizedError {
        case emptyPayload
        case noOriginal
        case openFailed(Int32)
        case writeFailed(Int32)
        case truncateFailed(Int32)
        case syncFailed(Int32)
        case verifyFailed
        case metadataChanged
        case invalidPlist(String)

        var errorDescription: String? {
            switch self {
            case .emptyPayload: return "拒绝写入 0 字节数据"
            case .noOriginal: return "读取当前文件失败，已中止写入"
            case .openFailed(let e): return "打开文件失败 (errno=\(e))"
            case .writeFailed(let e): return "写入失败 (errno=\(e))"
            case .truncateFailed(let e): return "尾部截断失败 (errno=\(e))"
            case .syncFailed(let e): return "F_FULLFSYNC 落盘失败 (errno=\(e))"
            case .verifyFailed: return "写后读回校验不一致，已回滚"
            case .metadataChanged: return "写入破坏了 inode/属主/权限（这会让系统在重启后重建缓存），已回滚"
            case .invalidPlist(let reason): return "数据不是合法 plist：\(reason)"
            }
        }
    }

    /// 读取当前系统文件 → 合并 CacheExtra 改动 → 快照 → 原位写入。
    /// 返回写入前的原始字节（供调用方回滚）。
    @discardableResult
    static func applyCacheExtra(_ edits: [String: Any],
                                removing removals: [String] = [],
                                workspace: WorkspacePaths,
                                note: String) throws -> Data {
        try checkEdits(edits)
        let url = URL(fileURLWithPath: MGPath.systemGestalt)
        guard let before = try? Data(contentsOf: url) else { throw WriteError.noOriginal }
        guard var dict = parse(before) else { throw WriteError.invalidPlist("当前文件无法解析") }

        var extra = (dict["CacheExtra"] as? [String: Any]) ?? [:]
        for (key, value) in edits { extra[key] = value }
        for key in removals { extra.removeValue(forKey: key) }
        dict["CacheExtra"] = extra

        // 只有 CacheExtra 允许变，其余顶层键（CacheVersion / CacheUUID / CacheData …）
        // 必须完全一致。任何一处被改动都会让 mobilegestaltd 判定缓存非法并整份重建。
        let baseline = parse(before) ?? [:]
        for key in baseline.keys where key != "CacheExtra" {
            guard let lhs = baseline[key] as? NSObject,
                  let rhs = dict[key] as? NSObject,
                  lhs.isEqual(rhs) else {
                throw WriteError.invalidPlist("顶层键 (key) 在重组后发生变化，已拦截写入")
            }
        }
        guard baseline.keys.count == dict.keys.count else {
            throw WriteError.invalidPlist("顶层键数量从 (baseline.keys.count) 变为 \(dict.keys.count)，已拦截写入")
        }

        guard let after = try? PropertyListSerialization.data(fromPropertyList: dict,
                                                              format: .binary,
                                                              options: 0) else {
            throw WriteError.invalidPlist("序列化失败")
        }
        let dir = containerDirectory(workspace)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snap = dir.appendingPathComponent("before-\(EventLog.stamp()).plist")
        try? before.write(to: snap, options: .atomic)

        try writeInPlace(after, to: url)
        return before
    }

    /// 真实修改机型几何：ArtworkTraits 里的 SubType 决定屏幕几何特征，
    /// ProductType 决定机型标识。这两项是"改分辨率 / 挪灵动岛"的实际杠杆。
    @discardableResult
    static func applyDeviceProfile(subtype: Int?,
                                   deviceName: String?,
                                   productType: String?,
                                   workspace: WorkspacePaths,
                                   note: String) throws -> Data {
        let url = URL(fileURLWithPath: MGPath.systemGestalt)
        guard let before = try? Data(contentsOf: url) else { throw WriteError.noOriginal }
        guard var dict = parse(before) else { throw WriteError.invalidPlist("当前文件无法解析") }
        var extra = (dict["CacheExtra"] as? [String: Any]) ?? [:]

        if let subtype {
            guard var artwork = extra["oPeik/9e8lQWMszEjbPzng"] as? [String: Any] else {
                throw WriteError.invalidPlist("ArtworkTraits 缺失，为防丢失屏幕特征已拦截写入")
            }
            artwork["ArtworkDeviceSubType"] = subtype
            if let deviceName, !deviceName.isEmpty {
                artwork["ArtworkDeviceProductDescription"] = deviceName
            }
            extra["oPeik/9e8lQWMszEjbPzng"] = artwork
        }
        if let deviceName, !deviceName.isEmpty {
            extra["Z/dqyWS6OZTRy10UcmUAhw"] = deviceName
            extra["bbtR9jQx50Fv5Af/affNtA"] = deviceName
        }
        if let productType, !productType.isEmpty {
            extra["h9jDsbgj7xIVeIQ8S3/X3Q"] = productType
        }

        dict["CacheExtra"] = extra
        guard let after = try? PropertyListSerialization.data(fromPropertyList: dict,
                                                              format: .binary,
                                                              options: 0) else {
            throw WriteError.invalidPlist("序列化失败")
        }
        let dir = containerDirectory(workspace)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? before.write(to: dir.appendingPathComponent("before-\(EventLog.stamp()).plist"), options: .atomic)

        try writeInPlace(after, to: url)
        return before
    }

    /// 读取当前 ArtworkTraits 与 ProductType。
    static func readDeviceProfile() -> (subtype: Int?, deviceName: String, productType: String) {
        guard let snapshot = readSystem(), let dict = parse(snapshot.data),
              let extra = dict["CacheExtra"] as? [String: Any] else {
            return (nil, "", "")
        }
        let artwork = extra["oPeik/9e8lQWMszEjbPzng"] as? [String: Any]
        let subtype = (artwork?["ArtworkDeviceSubType"] as? NSNumber)?.intValue
        let name = (artwork?["ArtworkDeviceProductDescription"] as? String) ?? ""
        let product = (extra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String) ?? ""
        return (subtype, name, product)
    }

    /// 读取 CacheExtra 里若干键的当前值。
    static func readCacheExtra(_ keys: [String]) -> [String: Any] {
        guard let snapshot = readSystem(), let dict = parse(snapshot.data),
              let extra = dict["CacheExtra"] as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for key in keys where extra[key] != nil { result[key] = extra[key] }
        return result
    }

    /// 写入前检查待改键是否落在黑名单里。
    static func checkEdits(_ edits: [String: Any]) throws {
        for key in edits.keys {
            if let reason = blockedReason(for: key) {
                throw WriteError.invalidPlist("拒绝写入 (key)：(reason)")
            }
        }
    }

    /// 校验：必须是 plist 字典，且含 CacheExtra（若原文件有）。
    static func validate(_ data: Data) throws {
        guard !data.isEmpty else { throw WriteError.emptyPayload }
        guard let dict = parse(data) else { throw WriteError.invalidPlist("无法反序列化") }
        if dict["CacheExtra"] == nil && dict["CacheData"] == nil {
            throw WriteError.invalidPlist("缺少 CacheExtra / CacheData")
        }
    }

    /// 原位覆盖写入：不先 ftruncate(0)，保留 inode / 属主 / 权限。
    /// 写入前后比对 st_ino / st_uid / st_gid / st_mode，任何一项变了都回滚——
    /// 这三项被破坏时系统会在重启后丢弃并重建整份缓存，表现为"改了又自己变回去"。
    static func writeInPlace(_ data: Data, to url: URL) throws {
        try validate(data)
        guard let original = try? Data(contentsOf: url) else { throw WriteError.noOriginal }

        var before = stat()
        guard stat(url.path, &before) == 0 else { throw WriteError.openFailed(errno) }

        let fd = url.path.withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
        guard fd >= 0 else { throw WriteError.openFailed(errno) }
        defer { close(fd) }

        do {
            try pwriteAll(fd, data)
            if data.count < original.count {
                guard ftruncate(fd, off_t(data.count)) == 0 else { throw WriteError.truncateFailed(errno) }
            }
            guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else { throw WriteError.syncFailed(errno) }
            guard lseek(fd, 0, SEEK_SET) == 0 else { throw WriteError.verifyFailed }
            let readback = try readAll(fd)
            guard readback == data else { throw WriteError.verifyFailed }

            // inode / 属主 / 权限必须原样保留，否则重启后系统会重建缓存
            var after = stat()
            guard stat(url.path, &after) == 0,
                  after.st_ino == before.st_ino,
                  after.st_uid == before.st_uid,
                  after.st_gid == before.st_gid,
                  (after.st_mode & 0o7777) == (before.st_mode & 0o7777) else {
                throw WriteError.metadataChanged
            }
        } catch {
            // 回滚
            _ = try? pwriteAll(fd, original)
            _ = ftruncate(fd, off_t(original.count))
            _ = fcntl(fd, F_FULLFSYNC)
            throw error
        }
    }

    private static func pwriteAll(_ fd: Int32, _ data: Data) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { throw WriteError.writeFailed(EFAULT) }
            var written = 0
            while written < data.count {
                let result = pwrite(fd, base.advanced(by: written), data.count - written, off_t(written))
                if result > 0 { written += result; continue }
                if result < 0 && errno == EINTR { continue }
                throw WriteError.writeFailed(errno)
            }
        }
    }

    private static func readAll(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 { data.append(buffer, count: count); continue }
            if count == 0 { return data }
            if errno == EINTR { continue }
            throw WriteError.verifyFailed
        }
    }
}
