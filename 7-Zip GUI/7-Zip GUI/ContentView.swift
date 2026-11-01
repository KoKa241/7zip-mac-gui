//
//  ContentView.swift
//  7-Zip GUI
//
//  Created by Vlad on 01.11.2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Top 7-Zip Toolbar (Add, Extract, Test | Copy, Move, Delete, Info)
            SevenZipToolbarView(appViewModel: appViewModel)

            Divider()

            // Main File Manager Area (Single or Dual Panel)
            if appViewModel.isDualPane {
                HSplitView {
                    FilePanelView(
                        viewModel: appViewModel.leftPanel,
                        isActive: appViewModel.activePanelIndex == 0,
                        showActiveBorder: true
                    )
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                    FilePanelView(
                        viewModel: appViewModel.rightPanel,
                        isActive: appViewModel.activePanelIndex == 1,
                        showActiveBorder: true
                    )
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FilePanelView(
                    viewModel: appViewModel.leftPanel,
                    isActive: true,
                    showActiveBorder: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
        .sheet(isPresented: $appViewModel.showInfoSheet) {
            if let item = appViewModel.infoItem {
                FilePropertiesSheet(item: item, isPresented: $appViewModel.showInfoSheet)
                    .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
            }
        }
        .sheet(isPresented: $appViewModel.showSettingsSheet) {
            SettingsView(appViewModel: appViewModel, isPresented: $appViewModel.showSettingsSheet)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appViewModel: FileManagerAppViewModel())
    }
}
