//
//  FilePanelViewModel.swift
//  7-Zip GUI
//

import Foundation
import AppKit
import Combine

enum PanelViewMode: Int, CaseIterable {
    case largeIcons = 0
    case smallIcons = 1
    case list = 2
    case details = 3

    var title: String {
        switch self {
        case .largeIcons: return "Large Icons"
        case .smallIcons: return "Small Icons"
        case .list: return "List"
        case .details: return "Details"
        }
    }
}

final class FilePanelViewModel: ObservableObject {
    let panelIndex: Int
    @Published var currentPath: String = ""
    @Published var pathInput: String = ""
    @Published var items: [FileItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var focusedItem: FileItem? = nil
    @Published var sortColumn: FileSortColumn = .name
    @Published var sortAscending: Bool = true
    @Published var showHiddenFiles: Bool = false
    @Published var showDotsEntry: Bool = true
    @Published var flatView: Bool = false
    @Published var viewMode: PanelViewMode = .details
    @Published var errorMessage: String? = nil
    @Published var pathHistory: [String] = []

    // Archive browsing state
    @Published var currentArchivePath: String? = nil
    @Published var archiveInternalPrefix: String = "" // "" at archive root, or "folder/sub/"
    @Published var archivePassword: String? = nil
    private(set) var currentArchiveListing: ArchiveListing? = nil

    var isInsideArchive: Bool {
        currentArchivePath != nil
    }

    var onActivatePanel: (() -> Void)?
    weak var appViewModel: FileManagerAppViewModel?

    private static let previewDirsLock = NSLock()
    private static var createdPreviewDirectories: [URL] = []

    static func registerPreviewDirectory(_ url: URL) {
        previewDirsLock.lock()
        createdPreviewDirectories.append(url)
        previewDirsLock.unlock()
    }

    static func cleanupPreviewDirectories() {
        previewDirsLock.lock()
        let dirs = createdPreviewDirectories
        createdPreviewDirectories.removeAll()
        previewDirsLock.unlock()

        let fm = FileManager.default
        for dir in dirs {
            try? fm.removeItem(at: dir)
        }
    }

    init(panelIndex: Int, initialPath: String? = nil) {
        self.panelIndex = panelIndex
        let defaultPath = initialPath ?? FileManager.default.homeDirectoryForCurrentUser.path
        setupInitialHistory()
        navigateTo(path: defaultPath)
    }

    private func setupInitialHistory() {
        let fm = FileManager.default
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                             CommandLine.arguments.contains("-ui-testing")
        if isRunningTests {
            pathHistory = [fm.temporaryDirectory.path, "/"]
            return
        }
        let home = fm.homeDirectoryForCurrentUser.path
        // Avoid probing TCC-protected folders (Desktop, Documents, Downloads) with fileExists on startup
        pathHistory = [
            home,
            "/Applications",
            "/Volumes",
            "/"
        ]
    }

    var canGoUp: Bool {
        if isInsideArchive {
            return true
        }
        return currentPath != "/" && !currentPath.isEmpty
    }

    func navigateTo(url: URL) {
        navigateTo(path: url.path)
    }

    func navigateTo(path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let standardizedURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        let targetPath = standardizedURL.path

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir)

        if exists && !isDir.boolValue && SevenZipEngine.isArchiveFile(url: standardizedURL) {
            openArchive(at: targetPath)
            return
        }

        guard exists, isDir.boolValue else {
            errorMessage = "Folder not found: \(targetPath)"
            restorePathInput()
            return
        }

        // Exit archive state if we were inside an archive
        currentArchivePath = nil
        archiveInternalPrefix = ""
        currentArchiveListing = nil
        archivePassword = nil

        errorMessage = nil
        currentPath = targetPath
        pathInput = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"

        pathHistory.removeAll { $0 == targetPath }
        pathHistory.insert(targetPath, at: 0)
        if pathHistory.count > 20 {
            pathHistory.removeLast()
        }

        loadItems()
    }

    @discardableResult
    func openArchive(at archivePath: String, password: String? = nil) -> Bool {
        let standardizedArchivePath = URL(fileURLWithPath: archivePath).standardizedFileURL.path
        let effectivePassword = password ?? archivePassword
        do {
            let listing = try SevenZipEngine.shared.listArchive(at: standardizedArchivePath, password: effectivePassword)
            let parentDir = URL(fileURLWithPath: standardizedArchivePath).deletingLastPathComponent().standardizedFileURL.path
            currentPath = parentDir
            currentArchivePath = standardizedArchivePath
            archiveInternalPrefix = ""
            archivePassword = effectivePassword
            currentArchiveListing = listing
            errorMessage = nil
            updateArchivePathInput()
            loadArchiveItems()
            return true
        } catch SevenZipError.passwordRequired {
            if let prompted = promptForArchivePassword(archiveName: URL(fileURLWithPath: standardizedArchivePath).lastPathComponent) {
                return openArchive(at: standardizedArchivePath, password: prompted)
            }
            errorMessage = SevenZipError.passwordRequired.localizedDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func navigateInsideArchive(prefix: String) {
        guard isInsideArchive else { return }
        let normalized = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        archiveInternalPrefix = normalized.isEmpty ? "" : normalized + "/"
        updateArchivePathInput()
        loadArchiveItems()
    }

    private func updateArchivePathInput() {
        guard let archivePath = currentArchivePath else { return }
        if archiveInternalPrefix.isEmpty {
            pathInput = archivePath + "/"
        } else {
            pathInput = archivePath + "/" + archiveInternalPrefix
        }
    }

    private func restorePathInput() {
        if isInsideArchive {
            updateArchivePathInput()
        } else if !currentPath.isEmpty {
            pathInput = currentPath.hasSuffix("/") ? currentPath : currentPath + "/"
        }
    }

    func navigateUp() {
        guard canGoUp else { return }

        if let archivePath = currentArchivePath {
            if !archiveInternalPrefix.isEmpty {
                let trimmed = archiveInternalPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let lastSlash = trimmed.lastIndex(of: "/") {
                    let parentPrefix = String(trimmed[..<lastSlash])
                    navigateInsideArchive(prefix: parentPrefix)
                } else {
                    navigateInsideArchive(prefix: "")
                }
            } else {
                // Exit archive back to filesystem directory
                let archiveURL = URL(fileURLWithPath: archivePath)
                let parentURL = archiveURL.deletingLastPathComponent()
                navigateTo(url: parentURL)
                if let archiveItem = items.first(where: { $0.url.standardizedFileURL == archiveURL.standardizedFileURL }) {
                    updateSelection(ids: [archiveItem.id], focused: archiveItem)
                }
            }
            return
        }

        let currentURL = URL(fileURLWithPath: currentPath)
        let parentURL = currentURL.deletingLastPathComponent()
        navigateTo(url: parentURL)
    }

    func openRootFolder() {
        navigateTo(path: "/")
    }

    func refresh() {
        if let archivePath = currentArchivePath {
            let savedPrefix = archiveInternalPrefix
            if openArchive(at: archivePath, password: archivePassword) {
                if !savedPrefix.isEmpty {
                    navigateInsideArchive(prefix: savedPrefix)
                }
            }
        } else {
            loadItems()
        }
    }

    func openItem(_ item: FileItem) {
        if item.isParentEntry {
            navigateUp()
            return
        }

        if isInsideArchive {
            if item.isDirectory {
                let targetPrefix = item.archiveInternalPath ?? (archiveInternalPrefix + item.name)
                navigateInsideArchive(prefix: targetPrefix)
            } else if let archivePath = currentArchivePath, let internalPath = item.archiveInternalPath {
                guard SevenZipEngine.isSafeArchiveEntryPath(internalPath) else {
                    errorMessage = SevenZipError.unsafeArchivePath(internalPath).localizedDescription
                    return
                }
                let safeFileName = (item.name as NSString).lastPathComponent
                guard !safeFileName.isEmpty, safeFileName != "..", safeFileName != "." else { return }

                // Extract single file to a temporary preview directory and open with NSWorkspace
                let previewDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("7ZipPreview_\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
                    Self.registerPreviewDirectory(previewDir)
                    try SevenZipEngine.shared.extractArchive(
                        archivePath: archivePath,
                        destinationPath: previewDir.path,
                        internalPaths: [internalPath],
                        preserveDirectoryStructure: false,
                        overwriteMode: .overwriteAll,
                        password: archivePassword
                    )
                    let extractedURL = previewDir.appendingPathComponent(safeFileName)
                    let resolvedPreviewPrefix = previewDir.resolvingSymlinksInPath().path + "/"
                    let resolvedExtractedPath = extractedURL.resolvingSymlinksInPath().path
                    guard resolvedExtractedPath.hasPrefix(resolvedPreviewPrefix),
                          FileManager.default.fileExists(atPath: resolvedExtractedPath) else {
                        errorMessage = "Extracted file failed path safety verification."
                        return
                    }
                    if shouldAllowOpeningExtractedFile(at: extractedURL) {
                        NSWorkspace.shared.open(extractedURL)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            return
        }

        if item.isDirectory {
            navigateTo(url: item.url)
        } else if SevenZipEngine.isArchiveFile(url: item.url) {
            openArchive(at: item.url.path)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private static let executablePreviewExtensions: Set<String> = [
        "app", "command", "tool", "sh", "zsh", "bash", "csh", "pkg", "mpkg", "terminal", "workflow"
    ]

    private func shouldAllowOpeningExtractedFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let isExec = Self.executablePreviewExtensions.contains(ext) ||
                     FileManager.default.isExecutableFile(atPath: url.path)
        guard isExec else { return true }

        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                             CommandLine.arguments.contains("-ui-testing")
        if isRunningTests {
            return false
        }

        let alert = NSAlert()
        alert.messageText = "Executable File Inside Archive"
        alert.informativeText = "'\(url.lastPathComponent)' may be an executable application or script. Are you sure you want to open it?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptForArchivePassword(archiveName: String) -> String? {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                             CommandLine.arguments.contains("-ui-testing")
        if isRunningTests {
            return nil
        }
        let alert = NSAlert()
        alert.messageText = "Enter Password"
        alert.informativeText = "Archive '\(archiveName)' is encrypted. Enter password:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            return input.stringValue
        }
        return nil
    }

    // MARK: - Loading Archive Items

    private func loadArchiveItems() {
        guard let archivePath = currentArchivePath,
              let listing = currentArchiveListing else {
            items = []
            return
        }

        let archiveURL = URL(fileURLWithPath: archivePath)
        let folderIcon = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        folderIcon.size = NSSize(width: 16, height: 16)

        var loadedItems: [FileItem] = []

        if flatView {
            for entry in listing.entries {
                let entryName = (entry.path as NSString).lastPathComponent
                if !showHiddenFiles && entryName.hasPrefix(".") {
                    continue
                }
                let ext = (entryName as NSString).pathExtension
                let icon: NSImage
                if entry.isDirectory {
                    icon = folderIcon
                } else {
                    icon = NSWorkspace.shared.icon(forFileType: ext.isEmpty ? "public.data" : ext)
                    icon.size = NSSize(width: 16, height: 16)
                }

                let item = FileItem(
                    id: "archive://\(archivePath)/\(entry.path)",
                    url: archiveURL.appendingPathComponent(entry.path),
                    name: entry.path,
                    isDirectory: entry.isDirectory,
                    isParentEntry: false,
                    size: entry.size,
                    packedSize: entry.packedSize,
                    modifiedDate: entry.modifiedDate,
                    createdDate: entry.createdDate,
                    accessedDate: entry.accessedDate,
                    posixPermissions: entry.attributes,
                    fileType: entry.isDirectory ? "Folder" : (ext.isEmpty ? "File" : ext.uppercased()),
                    comment: entry.comment,
                    icon: icon,
                    archiveInternalPath: entry.path,
                    crc: entry.crc,
                    method: entry.method,
                    isEncrypted: entry.isEncrypted
                )
                loadedItems.append(item)
            }
        } else {
            // Hierarchical view at `archiveInternalPrefix`
            var directEntriesByName: [String: ArchiveEntry] = [:]
            var synthesizedFolderNames: Set<String> = []

            for entry in listing.entries {
                guard entry.path.hasPrefix(archiveInternalPrefix) else { continue }
                let remainder = String(entry.path.dropFirst(archiveInternalPrefix.count))
                guard !remainder.isEmpty else { continue }

                if let slashIdx = remainder.firstIndex(of: "/") {
                    let childFolderName = String(remainder[..<slashIdx])
                    if !childFolderName.isEmpty {
                        synthesizedFolderNames.insert(childFolderName)
                    }
                } else {
                    directEntriesByName[remainder] = entry
                    if entry.isDirectory {
                        synthesizedFolderNames.insert(remainder)
                    }
                }
            }

            // First add all folders at this level
            for folderName in synthesizedFolderNames {
                if !showHiddenFiles && folderName.hasPrefix(".") {
                    continue
                }
                let fullInternalPath = archiveInternalPrefix + folderName
                let explicitEntry = directEntriesByName[folderName]
                let item = FileItem(
                    id: "archive://\(archivePath)/\(fullInternalPath)",
                    url: archiveURL.appendingPathComponent(fullInternalPath),
                    name: folderName,
                    isDirectory: true,
                    isParentEntry: false,
                    size: 0,
                    packedSize: 0,
                    modifiedDate: explicitEntry?.modifiedDate,
                    createdDate: explicitEntry?.createdDate,
                    accessedDate: explicitEntry?.accessedDate,
                    posixPermissions: explicitEntry?.attributes ?? "D drwxr-xr-x",
                    fileType: "Folder",
                    comment: explicitEntry?.comment ?? "",
                    icon: folderIcon,
                    archiveInternalPath: fullInternalPath,
                    crc: explicitEntry?.crc ?? "",
                    method: explicitEntry?.method ?? "",
                    isEncrypted: explicitEntry?.isEncrypted ?? false
                )
                loadedItems.append(item)
            }

            // Next add all direct files at this level
            for (name, entry) in directEntriesByName where !entry.isDirectory && !synthesizedFolderNames.contains(name) {
                if !showHiddenFiles && name.hasPrefix(".") {
                    continue
                }
                let ext = (name as NSString).pathExtension
                let icon = NSWorkspace.shared.icon(forFileType: ext.isEmpty ? "public.data" : ext)
                icon.size = NSSize(width: 16, height: 16)

                let item = FileItem(
                    id: "archive://\(archivePath)/\(entry.path)",
                    url: archiveURL.appendingPathComponent(entry.path),
                    name: name,
                    isDirectory: false,
                    isParentEntry: false,
                    size: entry.size,
                    packedSize: entry.packedSize,
                    modifiedDate: entry.modifiedDate,
                    createdDate: entry.createdDate,
                    accessedDate: entry.accessedDate,
                    posixPermissions: entry.attributes,
                    fileType: ext.isEmpty ? "File" : ext.uppercased(),
                    comment: entry.comment,
                    icon: icon,
                    archiveInternalPath: entry.path,
                    crc: entry.crc,
                    method: entry.method,
                    isEncrypted: entry.isEncrypted
                )
                loadedItems.append(item)
            }
        }

        sortLoadedItems(&loadedItems)

        if showDotsEntry {
            let parentURL = archiveURL.deletingLastPathComponent()
            loadedItems.insert(FileItem.parentEntry(for: parentURL), at: 0)
        }

        items = loadedItems

        let validIDs = Set(loadedItems.map { $0.id })
        selectedIDs = selectedIDs.intersection(validIDs)
        if let focused = focusedItem, !validIDs.contains(focused.id) {
            focusedItem = nil
        }
    }

    // MARK: - Loading Filesystem Items

    func loadItems() {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: currentPath, isDirectory: true).resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentAccessDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey
        ]

        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        var loadedItems: [FileItem] = []

        do {
            let urls: [URL]
            if flatView {
                options.insert(.skipsPackageDescendants)
                if let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: keys, options: options) {
                    urls = enumerator.compactMap { $0 as? URL }
                } else {
                    urls = []
                }
            } else {
                urls = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: keys, options: options)
            }

            let resolvedPrefix = dirURL.path.hasSuffix("/") ? dirURL.path : dirURL.path + "/"

            for url in urls {
                let res = try? url.resourceValues(forKeys: Set(keys))
                let isDirectory = (res?.isDirectory ?? false) && !(res?.isPackage ?? false)
                let size = UInt64(res?.fileSize ?? 0)
                let allocatedSize = UInt64(res?.totalFileAllocatedSize ?? res?.fileSize ?? 0)
                let mTime = res?.contentModificationDate
                let cTime = res?.creationDate
                let aTime = res?.contentAccessDate
                let typeDesc = res?.localizedTypeDescription ?? (isDirectory ? "Folder" : url.pathExtension.uppercased())

                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let posixNum = (attrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
                let permString = Self.formatPosixPermissions(posixNum, isDirectory: isDirectory, isSymlink: res?.isSymbolicLink ?? false)

                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)

                let itemName: String
                if flatView {
                    let resolvedURLPath = url.resolvingSymlinksInPath().path
                    if resolvedURLPath.hasPrefix(resolvedPrefix) {
                        itemName = String(resolvedURLPath.dropFirst(resolvedPrefix.count))
                    } else {
                        itemName = url.lastPathComponent
                    }
                } else {
                    itemName = url.lastPathComponent
                }

                let item = FileItem(
                    id: url.path,
                    url: url,
                    name: itemName,
                    isDirectory: isDirectory,
                    isParentEntry: false,
                    size: isDirectory ? 0 : size,
                    packedSize: isDirectory ? 0 : allocatedSize,
                    modifiedDate: mTime,
                    createdDate: cTime,
                    accessedDate: aTime,
                    posixPermissions: permString,
                    fileType: typeDesc,
                    comment: "",
                    icon: icon
                )
                loadedItems.append(item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        sortLoadedItems(&loadedItems)

        if showDotsEntry && canGoUp {
            let parentURL = dirURL.deletingLastPathComponent()
            loadedItems.insert(FileItem.parentEntry(for: parentURL), at: 0)
        }

        items = loadedItems

        // Clean up selection
        let validIDs = Set(loadedItems.map { $0.id })
        selectedIDs = selectedIDs.intersection(validIDs)
        if let focused = focusedItem, !validIDs.contains(focused.id) {
            focusedItem = nil
        }
    }

    func setSort(column: FileSortColumn, ascending: Bool? = nil) {
        if let asc = ascending {
            sortColumn = column
            sortAscending = asc
        } else if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }

        var regularItems = items.filter { !$0.isParentEntry }
        sortLoadedItems(&regularItems)
        if let parentItem = items.first(where: { $0.isParentEntry }) {
            regularItems.insert(parentItem, at: 0)
        }
        items = regularItems
    }

    private func sortLoadedItems(_ list: inout [FileItem]) {
        list.sort { a, b in
            // In 7-Zip File Manager, directories are always grouped before files
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }

            let comparison: ComparisonResult
            switch sortColumn {
            case .name:
                comparison = a.name.localizedStandardCompare(b.name)
            case .size:
                if a.size == b.size {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.size < b.size ? .orderedAscending : .orderedDescending
                }
            case .packedSize:
                if a.packedSize == b.packedSize {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.packedSize < b.packedSize ? .orderedAscending : .orderedDescending
                }
            case .modified:
                let d1 = a.modifiedDate ?? .distantPast
                let d2 = b.modifiedDate ?? .distantPast
                if d1 == d2 {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = d1 < d2 ? .orderedAscending : .orderedDescending
                }
            case .created:
                let d1 = a.createdDate ?? .distantPast
                let d2 = b.createdDate ?? .distantPast
                if d1 == d2 {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = d1 < d2 ? .orderedAscending : .orderedDescending
                }
            case .accessed:
                let d1 = a.accessedDate ?? .distantPast
                let d2 = b.accessedDate ?? .distantPast
                if d1 == d2 {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = d1 < d2 ? .orderedAscending : .orderedDescending
                }
            case .attributes:
                comparison = a.posixPermissions.compare(b.posixPermissions)
            case .type:
                let extA = a.url.pathExtension.lowercased()
                let extB = b.url.pathExtension.lowercased()
                if extA == extB {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = extA.localizedStandardCompare(extB)
                }
            case .comment:
                comparison = a.comment.localizedStandardCompare(b.comment)
            }

            if sortAscending {
                return comparison == .orderedAscending
            } else {
                return comparison == .orderedDescending
            }
        }
    }

    func updateSelection(ids: Set<String>, focused: FileItem?) {
        selectedIDs = ids.filter { $0 != ".." }
        focusedItem = focused
    }

    func selectAll() {
        let regularItems = items.filter { !$0.isParentEntry }
        selectedIDs = Set(regularItems.map { $0.id })
        if focusedItem == nil || focusedItem?.isParentEntry == true {
            focusedItem = regularItems.first
        }
    }

    func deselectAll() {
        selectedIDs.removeAll()
        focusedItem = nil
    }

    func invertSelection() {
        let regularItems = items.filter { !$0.isParentEntry }
        let allIDs = Set(regularItems.map { $0.id })
        selectedIDs = allIDs.subtracting(selectedIDs)
        if selectedIDs.isEmpty {
            focusedItem = nil
        } else if let currentFocused = focusedItem, !selectedIDs.contains(currentFocused.id) {
            focusedItem = regularItems.first { selectedIDs.contains($0.id) }
        }
    }

    /// Returns currently selected items, or the focused item if selection is empty (excluding "..")
    var effectiveSelectedItems: [FileItem] {
        let selected = items.filter { selectedIDs.contains($0.id) && !$0.isParentEntry }
        if !selected.isEmpty {
            return selected
        }
        if let focused = focusedItem, !focused.isParentEntry {
            return [focused]
        }
        return []
    }

    // MARK: - 7-Zip Status Bar Metrics

    var totalObjectCount: Int {
        items.filter { !$0.isParentEntry }.count
    }

    var selectedObjectCount: Int {
        selectedIDs.count
    }

    var statusObjectsText: String {
        "\(selectedObjectCount) / \(totalObjectCount) object(s) selected"
    }

    var statusSelectedSizeText: String {
        guard !selectedIDs.isEmpty else { return "" }
        let total = items
            .filter { selectedIDs.contains($0.id) && !$0.isDirectory }
            .reduce(UInt64(0)) { $0 + $1.size }
        return FileItem.format7ZipNumber(total)
    }

    var statusFocusedSizeText: String {
        guard let focused = focusedItem, !focused.isParentEntry, !focused.isDirectory else { return "" }
        return FileItem.format7ZipNumber(focused.size)
    }

    var statusFocusedDateText: String {
        guard let focused = focusedItem, !focused.isParentEntry else { return "" }
        return focused.formattedModifiedDate
    }

    static func formatPosixPermissions(_ mode: UInt16, isDirectory: Bool, isSymlink: Bool) -> String {
        var chars: [Character] = []
        if isSymlink {
            chars.append("l")
        } else if isDirectory {
            chars.append("d")
        } else {
            chars.append("-")
        }

        let perms: [(UInt16, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        for (mask, ch) in perms {
            chars.append((mode & mask) != 0 ? ch : "-")
        }
        return String(chars)
    }
}
