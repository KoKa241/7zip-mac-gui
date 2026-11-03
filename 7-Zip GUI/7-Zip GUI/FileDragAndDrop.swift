//
//  FileDragAndDrop.swift
//  7-Zip GUI
//
//  Drag & drop support:
//  - Dragging files between the two panels (copy / move).
//  - Dragging files out to Finder and other apps (file URLs for disk items,
//    file promises for items inside an archive, extracted on demand).
//  - Dropping files from Finder / other apps (file URLs and file promises).
//

import AppKit
import UniformTypeIdentifiers

// MARK: - Conflict Resolution

enum DropConflictResolution {
    case keepBoth
    case replace
    case skip
}

// MARK: - Drop Planning

enum FileDropPlanner {
    /// Reads file URLs from a dragging pasteboard.
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return objects.map { $0.standardizedFileURL }
    }

    /// Reads file promise receivers (e.g. from Mail, Photos, browsers, or another archive panel).
    static func promiseReceivers(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        return pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
    }

    /// Sources that would actually change location (items already inside `destination` are ignored).
    static func effectiveSources(_ sources: [URL], destination: URL) -> [URL] {
        let dest = destination.standardizedFileURL
        return sources.filter { $0.standardizedFileURL.deletingLastPathComponent() != dest }
    }

    /// Returns true if `destination` is one of the sources or lies inside a source folder.
    static func destinationIsInsideSources(_ sources: [URL], destination: URL) -> Bool {
        let destPath = destination.standardizedFileURL.path
        for src in sources {
            let srcPath = src.standardizedFileURL.path
            if destPath == srcPath || destPath.hasPrefix(srcPath.hasSuffix("/") ? srcPath : srcPath + "/") {
                return true
            }
        }
        return false
    }

    /// Finder-like semantics: move on the same volume, copy across volumes.
    /// Option (⌥) forces copy, Command (⌘) forces move.
    static func operation(for sources: [URL], destination: URL, sourceMask: NSDragOperation) -> NSDragOperation {
        guard !sources.isEmpty,
              !destinationIsInsideSources(sources, destination: destination) else {
            return []
        }
        let effective = effectiveSources(sources, destination: destination)
        guard !effective.isEmpty else { return [] }

        // Modifier keys narrow the mask: ⌥ → .copy only, ⌘ → .generic only
        if sourceMask == .copy {
            return .copy
        }
        if sourceMask == .generic || sourceMask == .move {
            return .move
        }

        let canMove = sourceMask.contains(.move) || sourceMask.contains(.generic)
        let canCopy = sourceMask.contains(.copy)

        if canMove && effective.allSatisfy({ isSameVolume($0, destination) }) {
            return .move
        }
        if canCopy {
            return .copy
        }
        return canMove ? .move : []
    }

    static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let volA = try? a.resourceValues(forKeys: keys).volumeIdentifier,
              let volB = try? b.resourceValues(forKeys: keys).volumeIdentifier else {
            return false
        }
        return volA.isEqual(volB)
    }

    /// Generates a Finder-style unique name: "name 2.ext", "name 3.ext", ...
    static func uniqueDestinationURL(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var counter = 2
        repeat {
            let suffix = ext.isEmpty ? " \(counter)" : " \(counter).\(ext)"
            var truncatedStem = stem
            let maxStemBytes = max(1, 255 - suffix.utf8.count)
            while truncatedStem.utf8.count > maxStemBytes && !truncatedStem.isEmpty {
                truncatedStem.removeLast()
            }
            candidate = directory.appendingPathComponent(truncatedStem + suffix)
            counter += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Copies or moves `sources` into `destination`, resolving name conflicts with `resolution`.
    /// Returns a list of human-readable error messages (empty on full success).
    static func transfer(
        _ sources: [URL],
        to destination: URL,
        isMove: Bool,
        resolution: DropConflictResolution
    ) -> [String] {
        let fm = FileManager.default
        let destFolder = destination.standardizedFileURL
        var errors: [String] = []

        for source in sources {
            let srcURL = source.standardizedFileURL
            let name = srcURL.lastPathComponent
            var dstURL = destFolder.appendingPathComponent(name).standardizedFileURL
            if srcURL == dstURL { continue }

            do {
                if fm.fileExists(atPath: dstURL.path) {
                    // Same inode (case-insensitive APFS / symlink) → nothing to do
                    let srcID = try? srcURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                    let dstID = try? dstURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                    if let s = srcID, let d = dstID, s.isEqual(d) {
                        continue
                    }

                    switch resolution {
                    case .skip:
                        continue
                    case .keepBoth:
                        dstURL = uniqueDestinationURL(for: name, in: destFolder)
                    case .replace:
                        // Prefer the Trash so a replaced item can be recovered
                        do {
                            try fm.trashItem(at: dstURL, resultingItemURL: nil)
                        } catch {
                            try fm.removeItem(at: dstURL)
                        }
                    }
                }

                if isMove {
                    try fm.moveItem(at: srcURL, to: dstURL)
                } else {
                    try fm.copyItem(at: srcURL, to: dstURL)
                }
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }
        return errors
    }
}

// MARK: - Archive Entry File Promises (drag out of an open archive)

struct ArchiveDragPayload {
    let archivePath: String
    let internalPath: String
    let fileName: String
    let password: String?
}

final class ArchiveEntryPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    static let shared = ArchiveEntryPromiseDelegate()

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "7-Zip GUI Drag Extraction"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    static func makeProvider(for item: FileItem, archivePath: String, password: String?) -> NSFilePromiseProvider? {
        guard let internalPath = item.archiveInternalPath,
              SevenZipEngine.isSafeArchiveEntryPath(internalPath) else {
            return nil
        }
        let safeName = (item.name as NSString).lastPathComponent
        guard !safeName.isEmpty, safeName != ".", safeName != ".." else { return nil }

        let fileType: String
        if item.isDirectory {
            fileType = UTType.folder.identifier
        } else {
            let ext = (safeName as NSString).pathExtension
            fileType = UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
        }

        let provider = NSFilePromiseProvider(fileType: fileType, delegate: shared)
        provider.userInfo = ArchiveDragPayload(
            archivePath: archivePath,
            internalPath: internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            fileName: safeName,
            password: password
        )
        return provider
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        return (filePromiseProvider.userInfo as? ArchiveDragPayload)?.fileName ?? "Untitled"
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        return queue
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let payload = filePromiseProvider.userInfo as? ArchiveDragPayload else {
            completionHandler(CocoaError(.fileWriteUnknown))
            return
        }
        do {
            try Self.extract(payload, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    /// Extracts a single archive entry (file or folder, recursively) into a private staging
    /// directory, then moves it to the promised destination URL.
    static func extract(_ payload: ArchiveDragPayload, to destinationURL: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("7ZipDrag_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try SevenZipEngine.shared.extractArchive(
            archivePath: payload.archivePath,
            destinationPath: staging.path,
            internalPaths: [payload.internalPath],
            preserveDirectoryStructure: true,
            overwriteMode: .overwriteAll,
            password: payload.password
        )

        let extracted = staging.appendingPathComponent(payload.internalPath).standardizedFileURL
        let stagingPrefix = staging.standardizedFileURL.path + "/"
        guard extracted.path.hasPrefix(stagingPrefix),
              (try? extracted.checkResourceIsReachable()) == true else {
            throw SevenZipError.unsafeArchivePath(payload.internalPath)
        }

        // Never overwrite an existing item at the promised location
        let finalURL: URL
        if fm.fileExists(atPath: destinationURL.path) {
            finalURL = FileDropPlanner.uniqueDestinationURL(
                for: destinationURL.lastPathComponent,
                in: destinationURL.deletingLastPathComponent()
            )
        } else {
            finalURL = destinationURL
        }
        try fm.moveItem(at: extracted, to: finalURL)
    }
}

// MARK: - App View Model Drop Handling

extension FileManagerAppViewModel {
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            CommandLine.arguments.contains("-ui-testing")
    }

    /// Handles file URLs dropped onto a panel (from the other panel, Finder, or any app).
    func handleDroppedFileURLs(_ urls: [URL], toDirectory destDir: String, isMove: Bool) {
        let destURL = URL(fileURLWithPath: destDir, isDirectory: true).standardizedFileURL
        guard !FileDropPlanner.destinationIsInsideSources(urls, destination: destURL) else {
            showMessage(title: isMove ? "Move" : "Copy", message: "Cannot place a folder inside itself.")
            return
        }
        let sources = FileDropPlanner.effectiveSources(urls, destination: destURL)
        guard !sources.isEmpty else { return }

        let conflicts = sources.filter {
            FileManager.default.fileExists(atPath: destURL.appendingPathComponent($0.lastPathComponent).path)
        }
        guard let resolution = askConflictResolution(conflictNames: conflicts.map { $0.lastPathComponent }) else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let errors = FileDropPlanner.transfer(sources, to: destURL, isMove: isMove, resolution: resolution)
            DispatchQueue.main.async {
                self?.refreshPanels()
                if !errors.isEmpty {
                    self?.showMessage(
                        title: isMove ? "Error Moving Files" : "Error Copying Files",
                        message: errors.joined(separator: "\n")
                    )
                }
            }
        }
    }

    /// Handles file promises (archive entries dragged from a panel, Mail attachments, Photos, etc.).
    /// Files are first received into a private staging folder, then moved into the destination
    /// so name conflicts can be resolved consistently.
    func handleDroppedFilePromises(_ receivers: [NSFilePromiseReceiver], toDirectory destDir: String) {
        let fm = FileManager.default
        let destURL = URL(fileURLWithPath: destDir, isDirectory: true).standardizedFileURL
        let staging = fm.temporaryDirectory
            .appendingPathComponent("7ZipDrop_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            showMessage(title: "Drop Failed", message: error.localizedDescription)
            return
        }

        let expected = receivers.reduce(0) { $0 + max(1, $1.fileTypes.count) }
        var completed = 0
        var received: [URL] = []
        var errors: [String] = []

        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated

        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: staging, options: [:], operationQueue: queue) { [weak self] fileURL, error in
                DispatchQueue.main.async {
                    if let error = error {
                        errors.append(error.localizedDescription)
                    } else {
                        received.append(fileURL)
                    }
                    completed += 1
                    guard completed >= expected else { return }

                    let batch = received
                    let batchErrors = errors
                    received.removeAll()
                    errors.removeAll()
                    self?.finishPromisedDrop(batch, staging: staging, destination: destURL, priorErrors: batchErrors)
                }
            }
        }
    }

    private func finishPromisedDrop(_ files: [URL], staging: URL, destination: URL, priorErrors: [String]) {
        let fm = FileManager.default
        let conflicts = files.filter {
            fm.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path)
        }
        guard let resolution = askConflictResolution(conflictNames: conflicts.map { $0.lastPathComponent }) else {
            try? fm.removeItem(at: staging)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let errors = priorErrors + FileDropPlanner.transfer(files, to: destination, isMove: true, resolution: resolution)
            try? fm.removeItem(at: staging)
            DispatchQueue.main.async {
                self?.refreshPanels()
                if !errors.isEmpty {
                    self?.showMessage(title: "Error Receiving Files", message: errors.joined(separator: "\n"))
                }
            }
        }
    }

    /// Asks the user how to handle name conflicts. Returns `nil` if the user cancelled.
    private func askConflictResolution(conflictNames: [String]) -> DropConflictResolution? {
        guard !conflictNames.isEmpty else { return .keepBoth }
        if isRunningTests { return .keepBoth }

        let alert = NSAlert()
        alert.alertStyle = .warning
        if conflictNames.count == 1 {
            alert.messageText = "An item named “\(conflictNames[0])” already exists in this location."
        } else {
            alert.messageText = "\(conflictNames.count) items with the same names already exist in this location."
        }
        alert.informativeText = "Replaced items are moved to the Trash."
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        case .alertThirdButtonReturn: return .skip
        default: return nil
        }
    }
}
