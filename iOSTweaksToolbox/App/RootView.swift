//
//  RootView.swift
//  iOSTweaksToolbox
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack(path: $app.path) {
            DashboardView()
                .navigationDestination(for: AppModule.self) { module in
                    destination(for: module)
                }
        }
        .respringOverlay($app.shouldRespring, failed: $app.respringFailed)
        .alert("自动注销没有生效", isPresented: $app.respringFailed) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("第三方 App 在未越狱环境下无法可靠触发 SpringBoard 重启。改动已经写进系统缓存，请手动重启设备（长按电源键 + 任一音量键，滑动关机后再开机）使修改生效。")
        }
    }

    @ViewBuilder
    private func destination(for module: AppModule) -> some View {
        switch module {
        case .configurationEditor: PlistWorkspaceView()
        case .profileManager: ProfileManagerView()
        case .jsonEditor: JSONEditorWorkspaceView()
        case .hexEditor: HexWorkspaceView()
        case .dynamicIsland: IslandStudioView()
        case .displayLab: DisplayLabView()
        case .aodLab: AODLabView()
        case .gestalt: GestaltView()
        case .nfc: NFCView()
        case .deviceIdentity: DeviceIdentityView()
        case .fileManager: FileBrowserView()
        case .backup: BackupCenterView()
        case .deviceInfo: DeviceInfoView()
        case .diagnostics: DiagnosticsView()
        case .capabilities: CapabilityMatrixView()
        }
    }
}
