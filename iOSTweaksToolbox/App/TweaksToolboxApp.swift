//
//  TweaksToolboxApp.swift
//  iOSTweaksToolbox
//
//  App 入口。所有服务在 AppState 中构建一次，通过 environmentObject 下发。
//

import SwiftUI

@main
struct TweaksToolboxApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { await appState.bootstrap() }
        }
    }
}
