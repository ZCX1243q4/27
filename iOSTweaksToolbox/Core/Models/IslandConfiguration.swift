//
//  IslandConfiguration.swift
//  iOSTweaksToolbox
//
//  灵动岛布局参数。这里的数值只作用于 App 内模拟器。
//

import Foundation

struct IslandConfiguration: Codable, Equatable {
    var name: String = "Custom"
    var horizontalOffset: Double = 0
    var verticalOffset: Double = 0
    var width: Double = 126
    var height: Double = 36
    var cornerRadius: Double = 18
    var expandedWidth: Double = 371
    var expandedHeight: Double = 120
    var animationDuration: Double = 0.35

    static let original = IslandConfiguration(name: "Original Layout",
                                              horizontalOffset: 0, verticalOffset: 0,
                                              width: 126, height: 36, cornerRadius: 18,
                                              expandedWidth: 371, expandedHeight: 120,
                                              animationDuration: 0.35)

    static let airStyle = IslandConfiguration(name: "Air Style",
                                              horizontalOffset: 0, verticalOffset: -4,
                                              width: 108, height: 30, cornerRadius: 15,
                                              expandedWidth: 330, expandedHeight: 104,
                                              animationDuration: 0.28)

    static let compact = IslandConfiguration(name: "Compact Island",
                                             horizontalOffset: 0, verticalOffset: 2,
                                             width: 96, height: 28, cornerRadius: 14,
                                             expandedWidth: 300, expandedHeight: 92,
                                             animationDuration: 0.22)

    static let balanced = IslandConfiguration(name: "Balanced Layout",
                                              horizontalOffset: 0, verticalOffset: -1,
                                              width: 118, height: 34, cornerRadius: 17,
                                              expandedWidth: 356, expandedHeight: 112,
                                              animationDuration: 0.32)

    static let presets: [IslandConfiguration] = [.original, .airStyle, .compact, .balanced]
}

struct DisplayProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Custom Display Profile"
    var logicalWidth: Double
    var logicalHeight: Double
    var scale: Double
    var isSimulation: Bool = true
}

struct DisplaySnapshot: Codable {
    var boundsWidth: Double
    var boundsHeight: Double
    var nativeBoundsWidth: Double
    var nativeBoundsHeight: Double
    var scale: Double
    var nativeScale: Double
    var deviceModel: String
    var systemVersion: String
    var buildNumber: String
    var screenSizeInches: Double?
    var safeAreaTop: Double
    var safeAreaBottom: Double
}
