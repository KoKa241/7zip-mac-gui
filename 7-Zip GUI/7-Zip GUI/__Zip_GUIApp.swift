//
//  __Zip_GUIApp.swift
//  7-Zip GUI
//
//  Created by Vlad on 01.11.2026.
//

import SwiftUI

@main
struct __Zip_GUIApp: App {
    @StateObject private var appViewModel = FileManagerAppViewModel()

    var body: some Scene {
        WindowGroup("7-Zip") {
            ContentView(appViewModel: appViewModel)
        }
        .commands {
            SevenZipMenuCommands(appViewModel: appViewModel)
        }
    }
}

struct SevenZipMenuCommands: Commands {
    @ObservedObject var appViewModel: FileManagerAppViewModel

    var body: some Commands {
        // App Preferences Menu (Cmd+,)
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appViewModel.showSettingsSheet = true
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        // File Menu Additions
        CommandGroup(after: .newItem) {
            Button("Open") {
                if let focused = appViewModel.activePanel.focusedItem {
                    appViewModel.activePanel.openItem(focused)
                }
            }
            .keyboardShortcut(.return, modifiers: [])

            Divider()

            Button("Add to Archive...") {
                appViewModel.actionAdd()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Extract...") {
                appViewModel.actionExtract()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Test Archive") {
                appViewModel.actionTest()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Copy To...") {
                appViewModel.actionCopy()
            }
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)), modifiers: [])

            Button("Move To...") {
                appViewModel.actionMove()
            }
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [])

            Button("Delete") {
                appViewModel.actionDelete()
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            Divider()

            Button("Create Folder...") {
                appViewModel.actionCreateFolder()
            }
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), modifiers: [])

            Button("Properties") {
                appViewModel.actionInfo()
            }
            .keyboardShortcut("i", modifiers: [.command])
        }

        // Edit Menu Selection Additions
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Select All") {
                appViewModel.activePanel.selectAll()
            }
            .keyboardShortcut("a", modifiers: [.command])

            Button("Deselect All") {
                appViewModel.activePanel.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button("Invert Selection") {
                appViewModel.activePanel.invertSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        // View Menu (matching 7-Zip View menu)
        CommandMenu("7-Zip View") {
            Menu("Sort By") {
                Button("Name") {
                    appViewModel.activePanel.setSort(column: .name)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF3FunctionKey)!)), modifiers: [.control])

                Button("Type") {
                    appViewModel.activePanel.setSort(column: .type)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!)), modifiers: [.control])

                Button("Date") {
                    appViewModel.activePanel.setSort(column: .modified)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)), modifiers: [.control])

                Button("Size") {
                    appViewModel.activePanel.setSort(column: .size)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [.control])
            }

            Divider()

            Toggle("Flat View", isOn: Binding(
                get: { appViewModel.activePanel.flatView },
                set: { newValue in
                    appViewModel.activePanel.flatView = newValue
                    appViewModel.activePanel.refresh()
                }
            ))

            Toggle("2 Panels", isOn: $appViewModel.isDualPane)
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF9FunctionKey)!)), modifiers: [])

            Toggle("Show Hidden Files", isOn: Binding(
                get: { appViewModel.activePanel.showHiddenFiles },
                set: { newValue in
                    appViewModel.leftPanel.showHiddenFiles = newValue
                    appViewModel.rightPanel.showHiddenFiles = newValue
                    appViewModel.leftPanel.refresh()
                    appViewModel.rightPanel.refresh()
                }
            ))
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Menu("Toolbars") {
                Toggle("Archive Toolbar", isOn: $appViewModel.showArchiveToolbar)
                Toggle("Standard Toolbar", isOn: $appViewModel.showStandardToolbar)
                Divider()
                Toggle("Large Buttons", isOn: $appViewModel.largeButtons)
                Toggle("Show Buttons Text", isOn: $appViewModel.showButtonsText)
                Divider()
                Picker("Icon Style", selection: $appViewModel.toolbarIconStyle) {
                    ForEach(ToolbarIconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            Menu("Theme") {
                Picker("Theme", selection: $appViewModel.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
            }

            Divider()

            Button("Options / Settings...") {
                appViewModel.showSettingsSheet = true
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Open Root Folder") {
                appViewModel.activePanel.openRootFolder()
            }
            .keyboardShortcut("\\", modifiers: [.command])

            Button("Up One Level") {
                appViewModel.activePanel.navigateUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])

            Button("Refresh") {
                appViewModel.activePanel.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        // Favorites / Bookmarks Menu
        CommandMenu("Favorites") {
            Button("Home") {
                appViewModel.activePanel.navigateTo(path: FileManager.default.homeDirectoryForCurrentUser.path)
            }
            Button("Desktop") {
                let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop")
                appViewModel.activePanel.navigateTo(path: path)
            }
            Button("Downloads") {
                let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
                appViewModel.activePanel.navigateTo(path: path)
            }
            Button("Documents") {
                let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Documents")
                appViewModel.activePanel.navigateTo(path: path)
            }
            Divider()
            Button("Applications (/Applications)") {
                appViewModel.activePanel.navigateTo(path: "/Applications")
            }
            Button("Volumes (/Volumes)") {
                appViewModel.activePanel.navigateTo(path: "/Volumes")
            }
            Button("Root (/)") {
                appViewModel.activePanel.navigateTo(path: "/")
            }
        }
    }
}
