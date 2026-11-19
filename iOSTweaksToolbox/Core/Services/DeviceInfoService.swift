//
//  DeviceInfoService.swift
//  iOSTweaksToolbox
//
//  设备信息。全部来自公开 API 与只读系统调用。
//

import Foundation
import UIKit
import Darwin

struct DeviceInfoReport: Codable {
    var marketingName: String
    var hardwareIdentifier: String
    var systemName: String
    var systemVersion: String
    var buildNumber: String
    var architecture: String
    var processorCount: Int
    var physicalMemory: Int64
    var diskTotal: Int64
    var diskFree: Int64
    var batteryLevel: Double
    var batteryState: String
    var thermalState: String
    var lowPowerMode: Bool
    var identifierForVendor: String
}

enum DeviceInfoService {
    static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
        }
        return identifier
    }

    static func buildNumber() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func architecture() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func marketingName(for hardware: String) -> String {
        // 只覆盖本项目关心的机型；未知型号原样返回，不做猜测。
        let table: [String: String] = [
            "iPhone17,5": "iPhone 16e",
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus"
        ]
        return table[hardware] ?? hardware
    }

    @MainActor
    static func report() -> DeviceInfoReport {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let fm = FileManager.default
        let attributes = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = (attributes?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0

        let batteryState: String
        switch device.batteryState {
        case .charging: batteryState = "充电中"
        case .full: batteryState = "已充满"
        case .unplugged: batteryState = "使用电池"
        default: batteryState = "未知"
        }

        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "正常"
        case .fair: thermal = "偏高"
        case .serious: thermal = "严重"
        case .critical: thermal = "临界"
        @unknown default: thermal = "未知"
        }

        let hardware = hardwareIdentifier()
        return DeviceInfoReport(marketingName: marketingName(for: hardware),
                                hardwareIdentifier: hardware,
                                systemName: device.systemName,
                                systemVersion: device.systemVersion,
                                buildNumber: buildNumber(),
                                architecture: architecture(),
                                processorCount: ProcessInfo.processInfo.processorCount,
                                physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
                                diskTotal: total,
                                diskFree: free,
                                batteryLevel: Double(device.batteryLevel),
                                batteryState: batteryState,
                                thermalState: thermal,
                                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                identifierForVendor: device.identifierForVendor?.uuidString ?? "不可用")
    }
}
