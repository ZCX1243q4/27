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
        case .deviceIdentity: DeviceIdentityView()
        case .fileManager: FileBrowserView()
        case .backup: BackupCenterView()
        case .deviceInfo: DeviceInfoView()
        case .diagnostics: DiagnosticsView()
        case .capabilities: CapabilityMatrixView()
        }
    }
}
