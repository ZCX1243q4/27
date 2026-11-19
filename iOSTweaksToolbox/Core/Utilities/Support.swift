//
//  Support.swift
//  iOSTweaksToolbox
//
//  跨模块的小工具：文件移动、ZIP 打包、尺寸格式化。
//

import Foundation
import UIKit

enum Support {
    /// 把改动过的条目移进回收目录（不直接删除）。
    @discardableResult
    static func moveToTrash(_ url: URL, workspace: WorkspacePaths) -> URL? {
        let fm = FileManager.default
        let folder = workspace.root.appendingPathComponent("Trash-\(EventLog.stamp())", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try fm.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// 只用公开 API 的目录打包（NSFileCoordinator 的 forUploading 生成 zip）。
    static func zip(folder: URL, to destination: URL) throws {
        let fm = FileManager.default
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading],
                               error: &coordinationError) { temporary in
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: temporary, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// 顶层可用的展示控制器，用于系统弹窗。
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    static func prompt(title: String,
                       message: String?,
                       placeholder: String?,
                       onCommit: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = placeholder }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            onCommit(alert.textFields?.first?.text ?? "")
        })
        topViewController()?.present(alert, animated: true)
    }

    static func confirm(title: String, message: String?, destructive: String = "删除",
                        onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: destructive, style: .destructive) { _ in onConfirm() })
        topViewController()?.present(alert, animated: true)
    }
}
