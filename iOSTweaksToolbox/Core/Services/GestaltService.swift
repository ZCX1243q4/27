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
            case .invalidPlist(let reason): return "数据不是合法 plist：\(reason)"
            }
        }
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
    static func writeInPlace(_ data: Data, to url: URL) throws {
        try validate(data)
        guard let original = try? Data(contentsOf: url) else { throw WriteError.noOriginal }

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
