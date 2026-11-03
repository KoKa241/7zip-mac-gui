//
//  SettingsView.swift
//  7-Zip GUI
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case hotkeys = "Hotkeys"

    var id: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    @Binding var isPresented: Bool
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("7-Zip Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                .frame(width: 200)
            }

            Divider()

            if selectedTab == .general {
                generalTabContent
            } else {
                hotkeysTabContent
            }

            Spacer(minLength: 4)

            Divider()

            HStack {
                Button("About 7-Zip GUI (Unofficial)...") {
                    appViewModel.showAboutSheet = true
                }
                if selectedTab == .hotkeys {
                    Button("Reset All to Defaults") {
                        KeyboardShortcuts.resetAll()
                    }
                }
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 470)
        .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
    }

    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Appearance / Theme Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Text("Theme:")
                        .font(.system(size: 13))
                        .frame(width: 110, alignment: .leading)

                    Picker("", selection: $appViewModel.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    Text("Toolbar Icons:")
                        .font(.system(size: 13))
                        .frame(width: 110, alignment: .leading)

                    Picker("", selection: $appViewModel.toolbarIconStyle) {
                        ForEach(ToolbarIconStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // 2. Toolbar & View Options
            VStack(alignment: .leading, spacing: 8) {
                Text("Toolbar & Panels")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Toggle("Show Archive Toolbar (Add, Extract, Test)", isOn: $appViewModel.showArchiveToolbar)
                Toggle("Show Standard Toolbar (Copy, Move, Delete, Info)", isOn: $appViewModel.showStandardToolbar)
                Toggle("Large Toolbar Buttons", isOn: $appViewModel.largeButtons)
                Toggle("Show Buttons Text", isOn: $appViewModel.showButtonsText)
                Toggle("Two Panels Mode (F9)", isOn: $appViewModel.isDualPane)
                Toggle("Show Hidden Files", isOn: Binding(
                    get: { appViewModel.activePanel.showHiddenFiles },
                    set: { newValue in
                        appViewModel.leftPanel.showHiddenFiles = newValue
                        appViewModel.rightPanel.showHiddenFiles = newValue
                        appViewModel.leftPanel.refresh()
                        appViewModel.rightPanel.refresh()
                    }
                ))
            }
        }
    }

    private var hotkeysTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Archive Operations
                VStack(alignment: .leading, spacing: 8) {
                    Text("Archive Operations")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    KeyboardShortcuts.Recorder("Add to Archive:", name: .addArchive)
                    KeyboardShortcuts.Recorder("Extract Archive:", name: .extractArchive)
                    KeyboardShortcuts.Recorder("Test Archive:", name: .testArchive)
                }

                Divider()

                // 2. File Operations
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Management")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    KeyboardShortcuts.Recorder("Copy To...:", name: .copyItems)
                    KeyboardShortcuts.Recorder("Move To...:", name: .moveItems)
                    KeyboardShortcuts.Recorder("Create Folder:", name: .createFolder)
                    KeyboardShortcuts.Recorder("Delete / Trash:", name: .deleteItems)
                    KeyboardShortcuts.Recorder("Properties / Info:", name: .showInfo)
                }

                Divider()

                // 3. View & Navigation
                VStack(alignment: .leading, spacing: 8) {
                    Text("View & Navigation")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    KeyboardShortcuts.Recorder("Toggle 2 Panels:", name: .toggleDualPane)
                    KeyboardShortcuts.Recorder("Up One Level:", name: .navigateUp)
                    KeyboardShortcuts.Recorder("Refresh Panel:", name: .refreshPanel)
                    KeyboardShortcuts.Recorder("Toggle Hidden Files:", name: .toggleHiddenFiles)
                }
            }
            .padding(.trailing, 8)
        }
    }
}

struct AboutSevenZipView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            Text("7-Zip GUI (Unofficial)")
                .font(.system(size: 19, weight: .bold))

            Text("Unofficial 7-Zip GUI for macOS")
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("GUI Version:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    Text("1.0 (macOS 11.0+ Universal)")
                        .font(.system(size: 12))
                }

                HStack(alignment: .top) {
                    Text("7-Zip Engine:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    Text("7-Zip 26.05 (7zz CLI by Igor Pavlov)")
                        .font(.system(size: 12))
                }

                HStack(alignment: .top) {
                    Text("Formats:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    Text("7z, ZIP, TAR, GZ, BZ2, XZ, RAR, ISO, DMG, PKG, XAR, CAB, ARJ, LZH, ZSTD, WIM")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top) {
                    Text("Disclaimer:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    Text("This application is an independent, unofficial macOS GUI wrapper around the open-source 7-Zip engine (licensed under GNU LGPL). 7-Zip is developed and copyrighted by Igor Pavlov.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            Divider()

            HStack {
                Spacer()
                Button("OK") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 80)
            }
        }
        .padding(20)
        .frame(width: 460, height: 460)
        .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
    }
}
