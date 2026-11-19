//
//  DisplayService.swift
//  iOSTweaksToolbox
//
//  读取真实的屏幕参数（公开 API）。
//

import UIKit

enum DisplayService {
    @MainActor
    static func snapshot() -> DisplaySnapshot {
        let screen = UIScreen.main
        let bounds = screen.bounds
        let native = screen.nativeBounds
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        let insets = window?.safeAreaInsets ?? .zero

        return DisplaySnapshot(boundsWidth: Double(bounds.width),
                               boundsHeight: Double(bounds.height),
                               nativeBoundsWidth: Double(native.width),
                               nativeBoundsHeight: Double(native.height),
                               scale: Double(screen.scale),
                               nativeScale: Double(screen.nativeScale),
                               deviceModel: DeviceInfoService.hardwareIdentifier(),
                               systemVersion: UIDevice.current.systemVersion,
                               buildNumber: DeviceInfoService.buildNumber(),
                               screenSizeInches: nil,
                               safeAreaTop: Double(insets.top),
                               safeAreaBottom: Double(insets.bottom))
    }

    /// 以真实参数为基准建立自定义方案；只是 App 内模拟数据。
    @MainActor
    static func baselineProfile() -> DisplayProfile {
        let snapshot = snapshot()
        return DisplayProfile(name: "Custom Display Profile",
                              logicalWidth: snapshot.boundsWidth,
                              logicalHeight: snapshot.boundsHeight,
                              scale: snapshot.scale)
    }
}
