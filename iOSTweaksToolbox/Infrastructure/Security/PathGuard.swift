//
//  PathGuard.swift
//  iOSTweaksToolbox
//
//  写入前的最后一道关卡。任何路径只要落在系统保护区、或落在
//  本 App 沙盒之外且没有用户授权，就直接拒绝，不做"尽力尝试"。
//

import Foundation

enum PathGuard {
    /// 唯一被允许经 worse_query 令牌写入的系统文件。
    static let mobileGestaltPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    /// 允许经令牌写入的另一条受控路径（分辨率画布）。
    static let resolutionPath = "/var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist"

    /// 无论权限如何都不允许写入的系统区域。
    static let protectedPrefixes: [String] = [
        "/System",
        "/bin", "/sbin", "/usr", "/etc", "/var", "/private",
        "/Applications",
        "/dev",
        "/cores"
    ]

    /// 允许写入的区域：本 App 沙盒 + 用户显式授权的目录。
    private(set) static var grantedRoots: Set<String> = []

    static func registerGrantedRoot(_ url: URL) {
        grantedRoots.insert(canonical(url.path))
    }

    static func revokeGrantedRoot(_ url: URL) {
        grantedRoots.remove(canonical(url.path))
    }

    static func canonical(_ path: String) -> String {
        var value = path
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static var sandboxRoots: [String] {
        let fm = FileManager.default
        var roots = [
            canonical(fm.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""),
            canonical(fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.path ?? ""),
            canonical(fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? ""),
            canonical(NSTemporaryDirectory())
        ]
        if let group = WorkspacePaths.appGroupURL() {
            roots.append(canonical(group.path))
        }
        return roots.filter { !$0.isEmpty }
    }

    static func isProtected(_ path: String) -> Bool {
        let value = canonical(path)
        if value == mobileGestaltPath { return false }    // 受控例外：需先持有 worse_query 令牌
        if value == resolutionPath { return false }       // 同上
        for prefix in protectedPrefixes {
            if value == prefix || value.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    static func isInsideAllowedRoot(_ path: String) -> Bool {
        let value = canonical(path)
        for root in sandboxRoots where value == root || value.hasPrefix(root + "/") { return true }
        for root in grantedRoots where value == root || value.hasPrefix(root + "/") { return true }
        return false
    }

    /// 写入/删除前统一检查。返回 nil 表示可以继续。
    static func denyReason(for path: String) -> String? {
        let value = canonical(path)
        guard value.hasPrefix("/") else { return "不是绝对路径" }
        if isProtected(value) {
            return "该路径位于系统保护区（\(protectedPrefixes.first { value == $0 || value.hasPrefix($0 + "/") } ?? value)），本工具不会写入"
        }
        if !isInsideAllowedRoot(value) {
            return "该路径不在本 App 沙盒或已授权目录内，系统权限也不允许写入"
        }
        return nil
    }

    static func check(_ path: String) throws {
        if let reason = denyReason(for: path) { throw ToolboxError.notWritable(reason) }
    }
}
