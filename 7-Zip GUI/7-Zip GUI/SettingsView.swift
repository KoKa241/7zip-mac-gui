//
//  SettingsView.swift
//  7-Zip GUI
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("7-Zip Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            Divider()

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

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 450, height: 360)
        .preferredColorScheme(appViewModel.appTheme.preferredColorScheme)
    }
}
