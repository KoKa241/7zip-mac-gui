//
//  FileManagerAppViewModel.swift
//  7-Zip GUI
//

import Foundation
import Combine
import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ToolbarIconStyle: String, CaseIterable, Identifiable {
    case modern = "modern"
    case classic = "classic"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modern: return "Modern (macOS)"
        case .classic: return "Classic (7-Zip)"
        }
    }
}

final class FileManagerAppViewModel: ObservableObject {
    @Published var isDualPane: Bool = false
    @Published var activePanelIndex: Int = 0

    // Theme & Appearance
    @Published var appTheme: AppTheme = .system {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: "7zip.appTheme")
            applyTheme()
        }
    }

    @Published var toolbarIconStyle: ToolbarIconStyle = .modern {
        didSet {
            UserDefaults.standard.set(toolbarIconStyle.rawValue, forKey: "7zip.toolbarIconStyle")
        }
    }

    @Published var showSettingsSheet: Bool = false

    // Toolbar configuration (matching 7-Zip View -> Toolbars options)
    @Published var showArchiveToolbar: Bool = true
    @Published var showStandardToolbar: Bool = true
    @Published var largeButtons: Bool = true
    @Published var showButtonsText: Bool = true

    // Dialog / Action notification banner or modal state
    @Published var activeAlertTitle: String? = nil
    @Published var activeAlertMessage: String? = nil
    @Published var showInfoSheet: Bool = false
    @Published var infoItem: FileItem? = nil

    let leftPanel: FilePanelViewModel
    let rightPanel: FilePanelViewModel

    private var cancellables = Set<AnyCancellable>()

    init() {
        let fm = FileManager.default
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                             CommandLine.arguments.contains("-ui-testing")
        let initialLeft: String
        let initialRight: String
        if isRunningTests {
            initialLeft = fm.temporaryDirectory.path
            initialRight = fm.temporaryDirectory.path
        } else {
            let home = fm.homeDirectoryForCurrentUser.path
            let desktop = (home as NSString).appendingPathComponent("Desktop")
            initialLeft = home
            initialRight = fm.fileExists(atPath: desktop) ? desktop : home
        }

        self.leftPanel = FilePanelViewModel(panelIndex: 0, initialPath: initialLeft)
        self.rightPanel = FilePanelViewModel(panelIndex: 1, initialPath: initialRight)

        if let savedTheme = UserDefaults.standard.string(forKey: "7zip.appTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.appTheme = theme
        }
        if let savedStyle = UserDefaults.standard.string(forKey: "7zip.toolbarIconStyle"),
           let style = ToolbarIconStyle(rawValue: savedStyle) {
            self.toolbarIconStyle = style
        }

        self.leftPanel.onActivatePanel = { [weak self] in
            self?.activePanelIndex = 0
        }
        self.rightPanel.onActivatePanel = { [weak self] in
            self?.activePanelIndex = 1
        }

        applyTheme()
    }

    func applyTheme() {
        guard let app = NSApp else { return }
        switch appTheme {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    var activePanel: FilePanelViewModel {
        if !isDualPane {
            return leftPanel
        }
        return activePanelIndex == 0 ? leftPanel : rightPanel
    }

    var targetPanel: FilePanelViewModel {
        if !isDualPane {
            return leftPanel
        }
        return activePanelIndex == 0 ? rightPanel : leftPanel
    }

    func toggleDualPane() {
        isDualPane.toggle()
        if !isDualPane {
            activePanelIndex = 0
        }
    }

    // MARK: - Toolbar Actions

    func actionAdd() {
        let panel = activePanel
        let selected = panel.items.filter { panel.selectedIDs.contains($0.id) }
        let names = selected.isEmpty ? (panel.focusedItem.map { [$0.name] } ?? []) : selected.map { $0.name }
        if names.isEmpty {
            showMessage(title: "Add to Archive", message: "Please select one or more files or folders to add to an archive.")
        } else {
            showMessage(title: "Add to Archive", message: "Selected \(names.count) item(s) in:\n\(panel.currentPath)\n\n(Archive creation dialog will be connected to 7-Zip engine in the next step.)")
        }
    }

    func actionExtract() {
        let panel = activePanel
        let selected = panel.items.filter { panel.selectedIDs.contains($0.id) }
        let targetItem = selected.first ?? panel.focusedItem
        if let item = targetItem, !item.isParentEntry {
            showMessage(title: "Extract Archive", message: "Extract '\(item.name)' to:\n\(targetPanel.currentPath)\n\n(Extraction engine will be connected in the next step.)")
        } else {
            showMessage(title: "Extract", message: "Please select an archive file to extract.")
        }
    }

    func actionTest() {
        let panel = activePanel
        let selected = panel.items.filter { panel.selectedIDs.contains($0.id) }
        let targetItem = selected.first ?? panel.focusedItem
        if let item = targetItem, !item.isParentEntry {
            showMessage(title: "Test Archive", message: "Testing archive '\(item.name)'...\n\n(7-Zip integrity test will be connected in the next step.)")
        } else {
            showMessage(title: "Test", message: "Please select an archive or file to test.")
        }
    }

    func actionCopy() {
        let src = activePanel
        let selected = src.items.filter { src.selectedIDs.contains($0.id) }
        let itemsToCopy = selected.isEmpty ? (src.focusedItem.map { [$0] } ?? []).filter { !$0.isParentEntry } : selected
        guard !itemsToCopy.isEmpty else {
            showMessage(title: "Copy", message: "You must select one or more files or folders.")
            return
        }

        let destDir = isDualPane ? targetPanel.currentPath : src.currentPath
        showMessage(
            title: "Copy",
            message: "Copy \(itemsToCopy.count) item(s) from:\n\(src.currentPath)\n\nTo:\n\(destDir)"
        )
    }

    func actionMove() {
        let src = activePanel
        let selected = src.items.filter { src.selectedIDs.contains($0.id) }
        let itemsToMove = selected.isEmpty ? (src.focusedItem.map { [$0] } ?? []).filter { !$0.isParentEntry } : selected
        guard !itemsToMove.isEmpty else {
            showMessage(title: "Move", message: "You must select one or more files or folders.")
            return
        }

        let destDir = isDualPane ? targetPanel.currentPath : src.currentPath
        showMessage(
            title: "Move",
            message: "Move \(itemsToMove.count) item(s) from:\n\(src.currentPath)\n\nTo:\n\(destDir)"
        )
    }

    func actionDelete() {
        let src = activePanel
        let selected = src.items.filter { src.selectedIDs.contains($0.id) }
        let itemsToDelete = selected.isEmpty ? (src.focusedItem.map { [$0] } ?? []).filter { !$0.isParentEntry } : selected
        guard !itemsToDelete.isEmpty else {
            showMessage(title: "Delete", message: "You must select one or more files or folders to delete.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Confirm File Delete"
        if itemsToDelete.count == 1, let single = itemsToDelete.first {
            alert.informativeText = "Are you sure you want to move '\(single.name)' to the Trash?"
        } else {
            alert.informativeText = "Are you sure you want to move these \(itemsToDelete.count) items to the Trash?"
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            var errors: [String] = []
            for item in itemsToDelete {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                }
            }
            src.refresh()
            if isDualPane {
                targetPanel.refresh()
            }
            if !errors.isEmpty {
                showMessage(title: "Error Deleting", message: errors.joined(separator: "\n"))
            }
        }
    }

    func actionInfo() {
        let src = activePanel
        let selected = src.items.filter { src.selectedIDs.contains($0.id) }
        if let item = selected.first ?? src.focusedItem, !item.isParentEntry {
            infoItem = item
            showInfoSheet = true
        } else {
            // Show current folder properties
            let url = URL(fileURLWithPath: src.currentPath)
            let icon = NSWorkspace.shared.icon(forFile: src.currentPath)
            let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .contentAccessDateKey])
            infoItem = FileItem(
                id: src.currentPath,
                url: url,
                name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent,
                isDirectory: true,
                isParentEntry: false,
                size: 0,
                packedSize: 0,
                modifiedDate: res?.contentModificationDate,
                createdDate: res?.creationDate,
                accessedDate: res?.contentAccessDate,
                posixPermissions: "drwxr-xr-x",
                fileType: "Folder",
                comment: "",
                icon: icon
            )
            showInfoSheet = true
        }
    }

    func actionCreateFolder() {
        let src = activePanel
        let alert = NSAlert()
        alert.messageText = "Create Folder"
        alert.informativeText = "Folder name:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = "New Folder"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            let folderName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else { return }
            let newFolderURL = URL(fileURLWithPath: src.currentPath).appendingPathComponent(folderName)
            do {
                try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
                src.refresh()
            } catch {
                showMessage(title: "Error Creating Folder", message: error.localizedDescription)
            }
        }
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
