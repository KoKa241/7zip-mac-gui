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

    var onActivatePanel: (() -> Void)?

    init(panelIndex: Int, initialPath: String? = nil) {
        self.panelIndex = panelIndex
        let defaultPath = initialPath ?? FileManager.default.homeDirectoryForCurrentUser.path
        setupInitialHistory()
        navigateTo(path: defaultPath)
    }

    private func setupInitialHistory() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var defaults: [String] = [
            home,
            (home as NSString).appendingPathComponent("Desktop"),
            (home as NSString).appendingPathComponent("Downloads"),
            (home as NSString).appendingPathComponent("Documents"),
            "/Applications",
            "/Volumes",
            "/"
        ]
        defaults = defaults.filter { fm.fileExists(atPath: $0) }
        pathHistory = defaults
    }

    var canGoUp: Bool {
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
        guard FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir), isDir.boolValue else {
            errorMessage = "Folder not found: \(targetPath)"
            pathInput = currentPath
            return
        }

        errorMessage = nil
        currentPath = targetPath
        pathInput = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"

        if !pathHistory.contains(targetPath) {
            pathHistory.insert(targetPath, at: 0)
            if pathHistory.count > 20 {
                pathHistory.removeLast()
            }
        }

        loadItems()
    }

    func navigateUp() {
        guard canGoUp else { return }
        let currentURL = URL(fileURLWithPath: currentPath)
        let parentURL = currentURL.deletingLastPathComponent()
        navigateTo(url: parentURL)
    }

    func openRootFolder() {
        navigateTo(path: "/")
    }

    func refresh() {
        loadItems()
    }

    func openItem(_ item: FileItem) {
        if item.isParentEntry {
            navigateUp()
        } else if item.isDirectory {
            navigateTo(url: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func loadItems() {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: currentPath, isDirectory: true)
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
                    let prefix = dirURL.path.hasSuffix("/") ? dirURL.path : dirURL.path + "/"
                    if url.path.hasPrefix(prefix) {
                        itemName = String(url.path.dropFirst(prefix.count))
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
        // Exclude ".." from operated selection count if needed, or keep it consistent with 7-Zip
        selectedIDs = ids.filter { $0 != ".." }
        focusedItem = focused
    }

    func selectAll() {
        selectedIDs = Set(items.filter { !$0.isParentEntry }.map { $0.id })
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func invertSelection() {
        let allIDs = Set(items.filter { !$0.isParentEntry }.map { $0.id })
        selectedIDs = allIDs.subtracting(selectedIDs)
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

    private static func formatPosixPermissions(_ mode: UInt16, isDirectory: Bool, isSymlink: Bool) -> String {
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
