//
//  SettingsView.swift
//  7-Zip GUI
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)

                Text("7-Zip Settings")
                    .font(.headline)

                Spacer()
            }

            Divider()

            // 1. Appearance / Theme Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("Theme:")
                        .frame(width: 120, alignment: .leading)

                    Picker("", selection: $appViewModel.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                }

                HStack {
                    Text("Toolbar Icons:")
                        .frame(width: 120, alignment: .leading)

                    Picker("", selection: $appViewModel.toolbarIconStyle) {
                        ForEach(ToolbarIconStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                }
            }

            Divider()

            // 2. Toolbar & View Options
            VStack(alignment: .leading, spacing: 8) {
                Text("Toolbar & Panels")
                    .font(.system(size: 13, weight: .semibold))
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

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
        .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
    }
}
