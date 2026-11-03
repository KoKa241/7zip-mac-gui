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

enum ActiveModalSheet: Identifiable {
    case info(FileItem)
    case settings
    case about
    case addArchive(sourceDirectory: String, sourceItems: [FileItem])
    case extractArchive(archivePath: String, internalPaths: [String]?, defaultDestination: String, initialPassword: String?)
    case copyMove(operation: CopyMoveOperationType, sourceItems: [FileItem], sourceArchivePath: String?, sourceArchivePassword: String?, defaultDestination: String)

    var id: String {
        switch self {
        case .info(let item):
            return "info_\(item.id)"
        case .settings:
            return "settings"
        case .about:
            return "about"
        case .addArchive(let dir, _):
            return "add_\(dir)"
        case .extractArchive(let path, _, _, _):
            return "extract_\(path)"
        case .copyMove(let op, _, _, _, _):
            return "copymove_\(op.title)"
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

    // Unified Modal Sheet presentation (ensures reliable sheet presentation on macOS 11+)
    @Published var activeModalSheet: ActiveModalSheet? = nil

    var showSettingsSheet: Bool {
        get {
            if case .settings = activeModalSheet { return true }
            return false
        }
        set {
            if newValue {
                activeModalSheet = .settings
            } else if case .settings = activeModalSheet {
                activeModalSheet = nil
            }
        }
    }

    var showAboutSheet: Bool {
        get {
            if case .about = activeModalSheet { return true }
            return false
        }
        set {
            if newValue {
                activeModalSheet = .about
            } else if case .about = activeModalSheet {
                activeModalSheet = nil
            }
        }
    }

    var showInfoSheet: Bool {
        get {
            if case .info = activeModalSheet { return true }
            return false
        }
        set {
            if !newValue, case .info = activeModalSheet {
                activeModalSheet = nil
            }
        }
    }

    // Toolbar configuration (matching 7-Zip View -> Toolbars options)
    @Published var showArchiveToolbar: Bool = true
    @Published var showStandardToolbar: Bool = true
    @Published var largeButtons: Bool = true
    @Published var showButtonsText: Bool = true

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
            initialLeft = home
            initialRight = home
        }

        self.leftPanel = FilePanelViewModel(panelIndex: 0, initialPath: initialLeft)
        self.rightPanel = FilePanelViewModel(panelIndex: 1, initialPath: initialRight)
        self.leftPanel.appViewModel = self
        self.rightPanel.appViewModel = self

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

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            SevenZipEngine.shared.terminateAllRunningProcesses()
            FilePanelViewModel.cleanupPreviewDirectories()
        }

        setupHotkeys()
        applyTheme()
    }

    // MARK: - Hotkeys Subscription

    func setupHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .extractArchive) { [weak self] in
            self?.actionExtract()
        }
        KeyboardShortcuts.onKeyUp(for: .addArchive) { [weak self] in
            self?.actionAdd()
        }
        KeyboardShortcuts.onKeyUp(for: .testArchive) { [weak self] in
            self?.actionTest()
        }
        KeyboardShortcuts.onKeyUp(for: .copyItems) { [weak self] in
            self?.actionCopy()
        }
        KeyboardShortcuts.onKeyUp(for: .moveItems) { [weak self] in
            self?.actionMove()
        }
        KeyboardShortcuts.onKeyUp(for: .createFolder) { [weak self] in
            self?.actionCreateFolder()
        }
        KeyboardShortcuts.onKeyUp(for: .deleteItems) { [weak self] in
            self?.actionDelete()
        }
        KeyboardShortcuts.onKeyUp(for: .showInfo) { [weak self] in
            self?.actionInfo()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDualPane) { [weak self] in
            self?.toggleDualPane()
        }
        KeyboardShortcuts.onKeyUp(for: .navigateUp) { [weak self] in
            self?.activePanel.navigateUp()
        }
        KeyboardShortcuts.onKeyUp(for: .refreshPanel) { [weak self] in
            self?.activePanel.refresh()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleHiddenFiles) { [weak self] in
            guard let self = self else { return }
            let newValue = !self.activePanel.showHiddenFiles
            self.leftPanel.showHiddenFiles = newValue
            self.rightPanel.showHiddenFiles = newValue
            self.leftPanel.refresh()
            self.rightPanel.refresh()
        }
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

    func refreshPanels() {
        leftPanel.refresh()
        if isDualPane {
            rightPanel.refresh()
        }
    }

    // MARK: - Toolbar Actions

    func actionAdd() {
        let panel = activePanel
        if panel.isInsideArchive {
            showMessage(
                title: "Add to Archive",
                message: "Cannot create a new archive directly from inside an open archive. Please navigate to a folder on disk first."
            )
            return
        }

        var itemsToAdd = panel.effectiveSelectedItems
        if itemsToAdd.isEmpty {
            // If no specific item is selected, add all items in the current folder
            itemsToAdd = panel.items.filter { !$0.isParentEntry }
        }

        guard !itemsToAdd.isEmpty else {
            showMessage(
                title: "Add to Archive",
                message: "The current folder is empty. Please navigate to a folder with files to add to an archive."
            )
            return
        }

        activeModalSheet = .addArchive(
            sourceDirectory: panel.currentPath,
            sourceItems: itemsToAdd
        )
    }

    func actionExtract() {
        let panel = activePanel

        if let openArchive = panel.currentArchivePath {
            let selected = panel.effectiveSelectedItems
            let internalPaths = selected.compactMap { $0.archiveInternalPath }
            let defaultDest = isDualPane && !targetPanel.isInsideArchive
                ? targetPanel.currentPath
                : URL(fileURLWithPath: openArchive).deletingLastPathComponent().path

            activeModalSheet = .extractArchive(
                archivePath: openArchive,
                internalPaths: internalPaths.isEmpty ? nil : internalPaths,
                defaultDestination: defaultDest,
                initialPassword: panel.archivePassword
            )
            return
        }

        let selected = panel.effectiveSelectedItems
        let archiveItem: FileItem?
        if let firstSelected = selected.first, !firstSelected.isDirectory, SevenZipEngine.isArchiveFile(url: firstSelected.url) {
            archiveItem = firstSelected
        } else {
            // Check if there is an archive in the current folder or let the user pick one via NSOpenPanel
            let archivesInFolder = panel.items.filter { !$0.isParentEntry && !$0.isDirectory && SevenZipEngine.isArchiveFile(url: $0.url) }
            if archivesInFolder.count == 1 {
                archiveItem = archivesInFolder.first
            } else {
                archiveItem = nil
            }
        }

        let archivePath: String
        if let item = archiveItem {
            archivePath = item.url.path
        } else if let pickedURL = promptToPickArchiveFile(title: "Select Archive to Extract", initialDirectory: panel.currentPath) {
            archivePath = pickedURL.path
        } else {
            return
        }

        let archiveBaseName = SevenZipEngine.stripArchiveExtensions(from: URL(fileURLWithPath: archivePath).lastPathComponent)
        let defaultDest: String
        if isDualPane && !targetPanel.isInsideArchive {
            defaultDest = targetPanel.currentPath
        } else {
            defaultDest = (panel.currentPath as NSString).appendingPathComponent(archiveBaseName)
        }

        activeModalSheet = .extractArchive(
            archivePath: archivePath,
            internalPaths: nil,
            defaultDestination: defaultDest,
            initialPassword: nil
        )
    }

    func actionTest() {
        let panel = activePanel
        let archiveToTest: String
        let internalPaths: [String]?
        let password: String?

        if let openArchive = panel.currentArchivePath {
            archiveToTest = openArchive
            let selected = panel.effectiveSelectedItems.compactMap { $0.archiveInternalPath }
            internalPaths = selected.isEmpty ? nil : selected
            password = panel.archivePassword
        } else if let item = panel.effectiveSelectedItems.first, !item.isDirectory, SevenZipEngine.isArchiveFile(url: item.url) {
            archiveToTest = item.url.path
            internalPaths = nil
            password = nil
        } else if let pickedURL = promptToPickArchiveFile(title: "Select Archive to Test", initialDirectory: panel.currentPath) {
            archiveToTest = pickedURL.path
            internalPaths = nil
            password = nil
        } else {
            return
        }

        do {
            let result = try SevenZipEngine.shared.testArchive(
                archivePath: archiveToTest,
                internalPaths: internalPaths,
                password: password
            )
            let archiveName = URL(fileURLWithPath: archiveToTest).lastPathComponent
            if result.isSuccess {
                showMessage(
                    title: "Test Archive — OK",
                    message: "Archive '\(archiveName)' passed the integrity check.\n\nEverything is Ok."
                )
            } else {
                showMessage(
                    title: "Test Archive — Failed",
                    message: "Errors detected in '\(archiveName)':\n\n\(result.output)"
                )
            }
        } catch {
            showMessage(title: "Test Archive — Error", message: error.localizedDescription)
        }
    }

    func actionCopy() {
        let src = activePanel
        let itemsToCopy = src.effectiveSelectedItems
        guard !itemsToCopy.isEmpty else {
            showMessage(title: "Copy", message: "Please select one or more files or folders in the file list first.")
            return
        }

        let destDir: String
        if isDualPane && !targetPanel.isInsideArchive {
            destDir = targetPanel.currentPath
        } else {
            destDir = src.currentPath
        }

        activeModalSheet = .copyMove(
            operation: .copy,
            sourceItems: itemsToCopy,
            sourceArchivePath: src.currentArchivePath,
            sourceArchivePassword: src.archivePassword,
            defaultDestination: destDir
        )
    }

    func actionMove() {
        let src = activePanel
        let itemsToMove = src.effectiveSelectedItems
        guard !itemsToMove.isEmpty else {
            showMessage(title: "Move", message: "Please select one or more files or folders in the file list first.")
            return
        }

        if let archivePath = src.currentArchivePath, !SevenZipEngine.isModifiableArchive(path: archivePath) {
            showMessage(title: "Move", message: "Moving items out of this archive format is not supported. Use Copy or Extract instead.")
            return
        }

        let destDir: String
        if isDualPane && !targetPanel.isInsideArchive {
            destDir = targetPanel.currentPath
        } else {
            destDir = src.currentPath
        }

        activeModalSheet = .copyMove(
            operation: .move,
            sourceItems: itemsToMove,
            sourceArchivePath: src.currentArchivePath,
            sourceArchivePassword: src.archivePassword,
            defaultDestination: destDir
        )
    }

    func performFilesystemCopyMove(items: [FileItem], toDirectory destDir: String, isMove: Bool) throws {
        let fm = FileManager.default
        let destFolderURL = URL(fileURLWithPath: destDir, isDirectory: true).standardizedFileURL

        for item in items {
            let srcURL = item.url.standardizedFileURL
            let dstURL = destFolderURL.appendingPathComponent(item.name).standardizedFileURL
            if srcURL == dstURL {
                continue
            }

            if fm.fileExists(atPath: dstURL.path) {
                // Check if srcURL and dstURL refer to the exact same inode (e.g. case-insensitive APFS or symlink)
                let srcID = try? srcURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                let dstID = try? dstURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                let isSameInode = (srcID != nil && dstID != nil && srcID!.isEqual(dstID!))

                if isSameInode {
                    if isMove && srcURL.lastPathComponent != dstURL.lastPathComponent {
                        try fm.moveItem(at: srcURL, to: dstURL)
                    }
                    continue
                }
                try fm.removeItem(at: dstURL)
            }

            if isMove {
                try fm.moveItem(at: srcURL, to: dstURL)
            } else {
                try fm.copyItem(at: srcURL, to: dstURL)
            }
        }
    }

    func actionDelete() {
        let src = activePanel
        let itemsToDelete = src.effectiveSelectedItems
        guard !itemsToDelete.isEmpty else {
            showMessage(title: "Delete", message: "Please select one or more files or folders in the file list to delete.")
            return
        }

        if let archivePath = src.currentArchivePath {
            guard SevenZipEngine.isModifiableArchive(path: archivePath) else {
                showMessage(title: "Delete", message: "This archive format is read-only and does not support deleting entries.")
                return
            }
            let internalPaths = itemsToDelete.compactMap { $0.archiveInternalPath }
            guard !internalPaths.isEmpty else { return }

            let alert = NSAlert()
            alert.messageText = "Confirm Delete from Archive"
            if itemsToDelete.count == 1, let single = itemsToDelete.first {
                alert.informativeText = "Are you sure you want to delete '\(single.name)' from the archive?"
            } else {
                alert.informativeText = "Are you sure you want to delete \(itemsToDelete.count) items from the archive?"
            }
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                do {
                    try SevenZipEngine.shared.deleteFromArchive(
                        archivePath: archivePath,
                        internalPaths: internalPaths,
                        password: src.archivePassword
                    )
                    refreshPanels()
                } catch {
                    showMessage(title: "Error Deleting from Archive", message: error.localizedDescription)
                }
            }
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
            refreshPanels()
            if !errors.isEmpty {
                showMessage(title: "Error Deleting", message: errors.joined(separator: "\n"))
            }
        }
    }

    func actionInfo() {
        let src = activePanel
        if let item = src.effectiveSelectedItems.first {
            activeModalSheet = .info(item)
        } else if let archivePath = src.currentArchivePath, let listing = src.currentArchiveListing {
            let url = URL(fileURLWithPath: archivePath)
            let icon = NSWorkspace.shared.icon(forFile: archivePath)
            let item = FileItem(
                id: archivePath,
                url: url,
                name: url.lastPathComponent,
                isDirectory: false,
                isParentEntry: false,
                size: listing.entries.reduce(0) { $0 + $1.size },
                packedSize: listing.physicalSize,
                modifiedDate: nil,
                createdDate: nil,
                accessedDate: nil,
                posixPermissions: listing.isSolid ? "Solid (+)" : "Non-solid (-)",
                fileType: "Archive (\(listing.archiveType))",
                comment: "",
                icon: icon,
                archiveInternalPath: nil,
                crc: "",
                method: listing.method,
                isEncrypted: false
            )
            activeModalSheet = .info(item)
        } else {
            let url = URL(fileURLWithPath: src.currentPath)
            let icon = NSWorkspace.shared.icon(forFile: src.currentPath)
            let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .contentAccessDateKey])
            let item = FileItem(
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
            activeModalSheet = .info(item)
        }
    }

    func actionCreateFolder() {
        let src = activePanel
        if src.isInsideArchive {
            showMessage(title: "Create Folder", message: "Creating empty folders directly inside an archive is not supported.")
            return
        }

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

    // MARK: - Extended Context Menu Actions

    func ArchiveBaseName(for items: [FileItem], in directory: String) -> String {
        if items.count == 1, let single = items.first {
            return single.isDirectory
                ? single.name
                : SevenZipEngine.stripArchiveExtensions(from: single.name)
        }
        let folderName = URL(fileURLWithPath: directory).lastPathComponent
        return folderName.isEmpty || folderName == "/" ? "archive" : folderName
    }

    func quickCompress(items: [FileItem], in directory: String, format: ArchiveFormat) {
        guard !items.isEmpty else { return }
        let baseName = ArchiveBaseName(for: items, in: directory)
        let archivePath = (directory as NSString).appendingPathComponent("\(baseName).\(format.fileExtension)")
        let relativeNames = items.map { $0.name }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try SevenZipEngine.shared.createArchive(
                    archivePath: archivePath,
                    format: format,
                    level: .normal,
                    solid: format == .sevenZ,
                    sourcePaths: relativeNames,
                    workingDirectory: directory
                )
                DispatchQueue.main.async {
                    self?.refreshPanels()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showMessage(title: "Compression Error", message: error.localizedDescription)
                }
            }
        }
    }

    func extractHere(archivePath: String, destinationDirectory: String, password: String? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try SevenZipEngine.shared.extractArchive(
                    archivePath: archivePath,
                    destinationPath: destinationDirectory,
                    internalPaths: nil,
                    preserveDirectoryStructure: true,
                    overwriteMode: .overwriteAll,
                    password: password
                )
                DispatchQueue.main.async {
                    self?.refreshPanels()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showMessage(title: "Extraction Error", message: error.localizedDescription)
                }
            }
        }
    }

    func extractToSubfolder(archivePath: String, parentDirectory: String, password: String? = nil) {
        let baseName = SevenZipEngine.stripArchiveExtensions(from: URL(fileURLWithPath: archivePath).lastPathComponent)
        let subDir = (parentDirectory as NSString).appendingPathComponent(baseName)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: subDir, isDirectory: true),
                    withIntermediateDirectories: true
                )
                try SevenZipEngine.shared.extractArchive(
                    archivePath: archivePath,
                    destinationPath: subDir,
                    internalPaths: nil,
                    preserveDirectoryStructure: true,
                    overwriteMode: .overwriteAll,
                    password: password
                )
                DispatchQueue.main.async {
                    self?.refreshPanels()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showMessage(title: "Extraction Error", message: error.localizedDescription)
                }
            }
        }
    }

    func actionRename(item: FileItem, in panel: FilePanelViewModel) {
        guard !panel.isInsideArchive, !item.isParentEntry else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for '\(item.name)':"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = item.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != item.name else { return }
            let dstURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: item.url, to: dstURL)
                refreshPanels()
            } catch {
                showMessage(title: "Error Renaming", message: error.localizedDescription)
            }
        }
    }

    func actionDuplicate(items: [FileItem], in panel: FilePanelViewModel) {
        guard !panel.isInsideArchive else { return }
        let fm = FileManager.default
        var errors: [String] = []

        for item in items where !item.isParentEntry {
            let dirURL = item.url.deletingLastPathComponent()
            let ext = item.url.pathExtension
            let stem = (item.name as NSString).deletingPathExtension

            var candidateName = Self.makeSafeDuplicateFilename(stem: stem, ext: ext, counter: nil)
            var counter = 2
            while fm.fileExists(atPath: dirURL.appendingPathComponent(candidateName).path) {
                candidateName = Self.makeSafeDuplicateFilename(stem: stem, ext: ext, counter: counter)
                counter += 1
            }

            do {
                try fm.copyItem(at: item.url, to: dirURL.appendingPathComponent(candidateName))
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        refreshPanels()
        if !errors.isEmpty {
            showMessage(title: "Error Duplicating", message: errors.joined(separator: "\n"))
        }
    }

    /// Ensures the generated duplicate filename never exceeds the 255 UTF-8 byte APFS/HFS+ limit (`NAME_MAX`).
    static func makeSafeDuplicateFilename(stem: String, ext: String, counter: Int?) -> String {
        let suffixCore = counter.map { " copy \($0)" } ?? " copy"
        let suffix = ext.isEmpty ? suffixCore : "\(suffixCore).\(ext)"
        let maxStemBytes = max(1, 255 - suffix.utf8.count)

        var truncatedStem = stem
        while truncatedStem.utf8.count > maxStemBytes && !truncatedStem.isEmpty {
            truncatedStem.removeLast()
        }
        return truncatedStem + suffix
    }

    func copyFilesToPasteboard(items: [FileItem]) {
        let urls = items.filter { !$0.isParentEntry && $0.archiveInternalPath == nil }.map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls)
    }

    private func promptToPickArchiveFile(title: String, initialDirectory: String) -> URL? {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                             CommandLine.arguments.contains("-ui-testing")
        if isRunningTests {
            return nil
        }
        let openPanel = NSOpenPanel()
        openPanel.title = title
        openPanel.message = "Select an archive file (.7z, .zip, .rar, .tar, .gz, .bz2, .xz, .dmg, .iso, etc.)"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = URL(fileURLWithPath: initialDirectory)
        if openPanel.runModal() == .OK {
            return openPanel.url
        }
        return nil
    }

    func showMessage(title: String, message: String) {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                             CommandLine.arguments.contains("-ui-testing")
        if isRunningTests {
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
