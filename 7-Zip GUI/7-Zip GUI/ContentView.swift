//
//  ContentView.swift
//  7-Zip GUI
//
//  Created by Vlad on 01.11.2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel

    private var sheetPresentationBinding: Binding<Bool> {
        Binding(
            get: { appViewModel.activeModalSheet != nil },
            set: { if !$0 { appViewModel.activeModalSheet = nil } }
        )
    }

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
        .onAppear {
            appViewModel.loadInitialPanels()
        }
        .sheet(item: $appViewModel.activeModalSheet) { sheet in
            switch sheet {
            case .info(let item):
                FilePropertiesSheet(item: item, isPresented: sheetPresentationBinding)
                    .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)

            case .settings:
                SettingsView(appViewModel: appViewModel, isPresented: sheetPresentationBinding)
                    .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)

            case .about:
                AboutSevenZipView(appViewModel: appViewModel, isPresented: sheetPresentationBinding)
                    .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)

            case .addArchive(let sourceDirectory, let sourceItems):
                AddArchiveSheet(
                    appViewModel: appViewModel,
                    sourceDirectory: sourceDirectory,
                    sourceItems: sourceItems,
                    isPresented: sheetPresentationBinding
                )
                .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)

            case .extractArchive(let archivePath, let internalPaths, let defaultDestination, let initialPassword):
                ExtractArchiveSheet(
                    appViewModel: appViewModel,
                    archivePath: archivePath,
                    internalPaths: internalPaths,
                    defaultDestination: defaultDestination,
                    initialPassword: initialPassword,
                    isPresented: sheetPresentationBinding
                )
                .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)

            case .copyMove(let operation, let sourceItems, let sourceArchivePath, let sourceArchivePassword, let defaultDestination):
                CopyMoveSheet(
                    appViewModel: appViewModel,
                    operation: operation,
                    sourceItems: sourceItems,
                    sourceArchivePath: sourceArchivePath,
                    sourceArchivePassword: sourceArchivePassword,
                    defaultDestination: defaultDestination,
                    isPresented: sheetPresentationBinding
                )
                .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appViewModel: FileManagerAppViewModel())
    }
}
