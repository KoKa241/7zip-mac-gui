//
//  SevenZipEngine.swift
//  7-Zip GUI
//

import Foundation
import Darwin

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZ = "7z"
    case zip = "zip"
    case tar = "tar"
    case wim = "wim"
    case xz = "xz"
    case gzip = "gzip"
    case bzip2 = "bzip2"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .wim: return "wim"
        case .xz: return "xz"
        case .gzip: return "gzip (.gz)"
        case .bzip2: return "bzip2 (.bz2)"
        }
    }

    var fileExtension: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .wim: return "wim"
        case .xz: return "xz"
        case .gzip: return "gz"
        case .bzip2: return "bz2"
        }
    }

    var supportsEncryption: Bool {
        switch self {
        case .sevenZ, .zip:
            return true
        default:
            return false
        }
    }

    var supportsHeaderEncryption: Bool {
        self == .sevenZ
    }
}

enum CompressionLevel: Int, CaseIterable, Identifiable {
    case store = 0
    case fastest = 1
    case fast = 3
    case normal = 5
    case maximum = 7
    case ultra = 9

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .store: return "0 - Store (No compression)"
        case .fastest: return "1 - Fastest"
        case .fast: return "3 - Fast"
        case .normal: return "5 - Normal"
        case .maximum: return "7 - Maximum"
        case .ultra: return "9 - Ultra"
        }
    }
}

enum ExtractOverwriteMode: String, CaseIterable, Identifiable {
    case overwriteAll = "-aoa"
    case skipExisting = "-aos"
    case autoRenameExtracted = "-aou"
    case autoRenameExisting = "-aot"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overwriteAll: return "Overwrite all existing files"
        case .skipExisting: return "Skip existing files"
        case .autoRenameExtracted: return "Auto rename extracted files"
        case .autoRenameExisting: return "Auto rename existing files"
        }
    }
}

struct ArchiveEntry: Equatable {
    let path: String          // Internal path inside archive, normalized without leading/trailing slash
    let isDirectory: Bool
    let size: UInt64
    let packedSize: UInt64
    let modifiedDate: Date?
    let createdDate: Date?
    let accessedDate: Date?
    let attributes: String
    let crc: String
    let isEncrypted: Bool
    let method: String
    let comment: String
}

struct ArchiveListing {
    let archivePath: String
    let archiveType: String
    let physicalSize: UInt64
    let headersSize: UInt64
    let method: String
    let isSolid: Bool
    let entries: [ArchiveEntry]
}

struct ArchiveTestResult {
    let isSuccess: Bool
    let archivePath: String
    let output: String
}

enum SevenZipError: LocalizedError, Equatable {
    case binaryNotFound
    case passwordRequired
    case unsafeArchivePath(String)
    case cancelled
    case commandFailed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "7-Zip engine binary (7zz) was not found in the application bundle."
        case .passwordRequired:
            return "This archive is encrypted and requires a password."
        case .unsafeArchivePath(let path):
            return "Blocked unsafe path traversal entry in archive: '\(path)'."
        case .cancelled:
            return "Operation was cancelled by the user."
        case .commandFailed(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "7-Zip operation failed with exit code \(code)."
            }
            return trimmed
        }
    }
}

/// Thread-safe cancellation token for long-running 7-Zip operations.
final class SevenZipOperationToken {
    private let lock = NSLock()
    private var _isCancelled: Bool = false
    private weak var process: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func attach(process: Process) {
        lock.lock()
        self.process = process
        let alreadyCancelled = _isCancelled
        lock.unlock()

        if alreadyCancelled {
            terminateProcess(process)
        }
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        let proc = process
        lock.unlock()

        if let proc = proc {
            terminateProcess(proc)
        }
    }

    private func terminateProcess(_ proc: Process) {
        guard proc.isRunning else { return }
        let pid = proc.processIdentifier
        proc.terminate() // SIGTERM
        if pid > 0 {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                if proc.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }
}

final class SevenZipEngine {
    static let shared = SevenZipEngine()

    private let activeProcessesLock = NSLock()
    private var activeProcesses: [Int32: Process] = [:]

    static let supportedArchiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz2",
        "xz", "txz", "zst", "tzst", "wim", "iso", "dmg", "pkg",
        "xar", "cab", "arj", "cpio", "rpm", "deb", "lzma", "lzh",
        "vhd", "vhdx", "squashfs", "apfs", "001", "taz", "tz"
    ]

    static func isArchiveFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedArchiveExtensions.contains(ext)
    }

    static func isModifiableArchive(path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["7z", "zip", "tar", "wim", "gz", "bz2", "xz"].contains(ext)
    }

    /// Strips single or compound archive extensions (e.g. "backup.tar.gz" -> "backup", "part.7z.001" -> "part").
    static func stripArchiveExtensions(from filename: String) -> String {
        let lower = filename.lowercased()
        let compoundSuffixes = [
            ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lzma",
            ".7z.001", ".zip.001", ".rar.001", ".tar.001"
        ]
        for suffix in compoundSuffixes {
            if lower.hasSuffix(suffix) && filename.count > suffix.count {
                return String(filename.dropLast(suffix.count))
            }
        }
        let stem = (filename as NSString).deletingPathExtension
        return stem.isEmpty ? filename : stem
    }

    /// Validates that an archive entry path does not escape the destination directory (Zip Slip protection).
    static func isSafeArchiveEntryPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        if path.hasPrefix("/") || path.hasPrefix("\\") {
            return false
        }
        let components = path.components(separatedBy: "/")
        for comp in components {
            if comp == ".." {
                return false
            }
        }
        return true
    }

    /// Prefixes relative filenames starting with `-` or `@` with `./` to prevent switch/listfile injection.
    static func sanitizeRelativePathArgument(_ path: String) -> String {
        if !path.hasPrefix("/") && (path.hasPrefix("-") || path.hasPrefix("@")) {
            return "./" + path
        }
        return path
    }

    /// Terminates all currently running child `7zz` processes (called on application exit).
    func terminateAllRunningProcesses() {
        activeProcessesLock.lock()
        let processes = Array(activeProcesses.values)
        activeProcesses.removeAll()
        activeProcessesLock.unlock()

        for proc in processes where proc.isRunning {
            let pid = proc.processIdentifier
            proc.terminate()
            if pid > 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    /// Resolves the path to the bundled `7zz` executable.
    func executableURL() throws -> URL {
        let fm = FileManager.default

        if let bundledURL = Bundle.main.url(forResource: "7zz", withExtension: nil),
           fm.fileExists(atPath: bundledURL.path) {
            ensureExecutablePermission(at: bundledURL)
            return bundledURL
        }

        let classBundle = Bundle(for: SevenZipEngine.self)
        if let testBundledURL = classBundle.url(forResource: "7zz", withExtension: nil),
           fm.fileExists(atPath: testBundledURL.path) {
            ensureExecutablePermission(at: testBundledURL)
            return testBundledURL
        }

        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceBinaryURL = sourceDir.appendingPathComponent("7zz")
        if fm.fileExists(atPath: sourceBinaryURL.path) {
            ensureExecutablePermission(at: sourceBinaryURL)
            return sourceBinaryURL
        }

        throw SevenZipError.binaryNotFound
    }

    private func ensureExecutablePermission(at url: URL) {
        let fm = FileManager.default
        if !fm.isExecutableFile(atPath: url.path) {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    // MARK: - Core Process Runner (Secure stdin password & Cancellation)

    @discardableResult
    func runCommand(
        arguments: [String],
        workingDirectory: String? = nil,
        stdinPassword: String? = nil,
        token: SevenZipOperationToken? = nil
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        if token?.isCancelled == true {
            throw SevenZipError.cancelled
        }

        let binURL = try executableURL()
        let process = Process()
        process.executableURL = binURL
        process.arguments = arguments

        if let workDir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workDir, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if let pwd = stdinPassword, !pwd.isEmpty {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            process.standardInput = FileHandle.nullDevice
            stdinPipe = nil
        }

        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        let pid = process.processIdentifier

        activeProcessesLock.lock()
        activeProcesses[pid] = process
        activeProcessesLock.unlock()

        token?.attach(process: process)

        // Write password to stdin pipe and close immediately so it never appears in ps aux
        if let pipe = stdinPipe, let pwd = stdinPassword {
            if var pwdData = (pwd + "\n").data(using: .utf8) {
                try? pipe.fileHandleForWriting.write(contentsOf: pwdData)
                pwdData.resetBytes(in: 0..<pwdData.count)
            }
            try? pipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        group.wait()

        activeProcessesLock.lock()
        activeProcesses.removeValue(forKey: pid)
        activeProcessesLock.unlock()

        if token?.isCancelled == true {
            throw SevenZipError.cancelled
        }

        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? String(decoding: stdoutData, as: UTF8.self)
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? String(decoding: stderrData, as: UTF8.self)

        return (process.terminationStatus, stdoutStr, stderrStr)
    }

    // MARK: - 1. List Archive (`7zz l -slt -spd -y -- <archivePath>`)

    func listArchive(at archivePath: String, password: String? = nil) throws -> ArchiveListing {
        let args = ["l", "-slt", "-spd", "-y", "--", archivePath]

        let result = try runCommand(arguments: args, stdinPassword: password)
        let combinedOutput = result.stdout + "\n" + result.stderr

        if result.exitCode != 0 {
            if isPasswordError(in: combinedOutput, exitCode: result.exitCode) {
                throw SevenZipError.passwordRequired
            }
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combinedOutput))
        }

        return Self.parseTechnicalListing(result.stdout, archivePath: archivePath)
    }

    private func isPasswordError(in output: String, exitCode: Int32) -> Bool {
        if output.contains("Enter password") ||
           output.localizedCaseInsensitiveContains("Wrong password") ||
           output.localizedCaseInsensitiveContains("Cannot open encrypted archive") ||
           output.localizedCaseInsensitiveContains("Can not open encrypted archive") ||
           output.localizedCaseInsensitiveContains("Data Error in encrypted file") {
            return true
        }
        return false
    }

    private static let knownTechnicalKeys: Set<String> = [
        "Path", "Folder", "Size", "Packed Size", "Modified", "Created", "Accessed",
        "Attributes", "Encrypted", "Comment", "CRC", "Method", "Block",
        "Characteristics", "Host OS", "Version", "Volume Index", "Offset",
        "Type", "Physical Size", "Headers Size", "Solid", "Blocks", "Symbolic Link"
    ]

    static func parseTechnicalListing(_ output: String, archivePath: String) -> ArchiveListing {
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n----------\n")

        var archiveType = URL(fileURLWithPath: archivePath).pathExtension
        var physicalSize: UInt64 = 0
        var headersSize: UInt64 = 0
        var archiveMethod = ""
        var isSolid = false

        if let headerPart = parts.first {
            for line in headerPart.components(separatedBy: "\n") {
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "Type": archiveType = val
                case "Physical Size": physicalSize = UInt64(val) ?? 0
                case "Headers Size": headersSize = UInt64(val) ?? 0
                case "Method": archiveMethod = val
                case "Solid": isSolid = (val == "+")
                default: break
                }
            }
        }

        guard parts.count > 1 else {
            return ArchiveListing(
                archivePath: archivePath,
                archiveType: archiveType,
                physicalSize: physicalSize,
                headersSize: headersSize,
                method: archiveMethod,
                isSolid: isSolid,
                entries: []
            )
        }

        let entriesText = parts[1]
        let rawBlocks = entriesText.components(separatedBy: "\n\n")
        var entries: [ArchiveEntry] = []

        for block in rawBlocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            var dict: [String: String] = [:]
            for line in lines {
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
                guard knownTechnicalKeys.contains(key) else { continue }
                let afterEq = line[line.index(after: eqIdx)...]
                // Strip only the single separator space after " = " so trailing spaces in filenames are preserved
                let val: String
                if afterEq.hasPrefix(" ") {
                    val = String(afterEq.dropFirst(1))
                } else {
                    val = String(afterEq)
                }
                if dict[key] == nil {
                    dict[key] = val
                }
            }

            guard let rawPath = dict["Path"], !rawPath.isEmpty else { continue }
            let hostOS = dict["Host OS"] ?? ""
            let slashNormalizedPath: String
            if hostOS.localizedCaseInsensitiveContains("Windows") || hostOS.localizedCaseInsensitiveContains("FAT") || hostOS.localizedCaseInsensitiveContains("NTFS") {
                slashNormalizedPath = rawPath.replacingOccurrences(of: "\\", with: "/")
            } else {
                slashNormalizedPath = rawPath
            }
            let normalizedPath = slashNormalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !normalizedPath.isEmpty else { continue }

            let folderFlag = dict["Folder"]?.trimmingCharacters(in: .whitespaces)
            let attr = (dict["Attributes"] ?? "").trimmingCharacters(in: .whitespaces)
            let isDir = (folderFlag == "+") || attr.hasPrefix("D") || rawPath.hasSuffix("/")
            let size = UInt64((dict["Size"] ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let packedSize = UInt64((dict["Packed Size"] ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let modified = parse7ZipDate(dict["Modified"]?.trimmingCharacters(in: .whitespaces))
            let created = parse7ZipDate(dict["Created"]?.trimmingCharacters(in: .whitespaces))
            let accessed = parse7ZipDate(dict["Accessed"]?.trimmingCharacters(in: .whitespaces))
            let crc = (dict["CRC"] ?? "").trimmingCharacters(in: .whitespaces)
            let encrypted = (dict["Encrypted"]?.trimmingCharacters(in: .whitespaces) == "+")
            let method = (dict["Method"] ?? "").trimmingCharacters(in: .whitespaces)
            let comment = dict["Comment"] ?? ""

            entries.append(ArchiveEntry(
                path: normalizedPath,
                isDirectory: isDir,
                size: isDir ? 0 : size,
                packedSize: isDir ? 0 : packedSize,
                modifiedDate: modified,
                createdDate: created,
                accessedDate: accessed,
                attributes: attr,
                crc: crc,
                isEncrypted: encrypted,
                method: method,
                comment: comment
            ))
        }

        return ArchiveListing(
            archivePath: archivePath,
            archiveType: archiveType,
            physicalSize: physicalSize,
            headersSize: headersSize,
            method: archiveMethod,
            isSolid: isSolid,
            entries: entries
        )
    }

    private static let dateFormatterWithFraction: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    private static let dateFormatterMinutes: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }()

    static func parse7ZipDate(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let trimmed: String
        if let dotIdx = raw.firstIndex(of: ".") {
            trimmed = String(raw[..<dotIdx])
        } else {
            trimmed = raw
        }
        if let date = dateFormatterWithFraction.date(from: trimmed) {
            return date
        }
        return dateFormatterMinutes.date(from: trimmed)
    }

    // MARK: - 2. Create / Add to Archive (`7zz a`)

    @discardableResult
    func createArchive(
        archivePath: String,
        format: ArchiveFormat,
        level: CompressionLevel,
        solid: Bool = true,
        password: String? = nil,
        encryptHeaders: Bool = false,
        sourcePaths: [String],
        workingDirectory: String? = nil,
        token: SevenZipOperationToken? = nil
    ) throws -> String {
        var args = [
            "a",
            "-t\(format.rawValue)",
            "-mx=\(level.rawValue)",
            "-spd",
            "-y"
        ]

        if format == .sevenZ && level != .store {
            args.append(solid ? "-ms=on" : "-ms=off")
        }

        let effectivePassword: String?
        if let pwd = password, !pwd.isEmpty, format.supportsEncryption {
            // Pass bare "-p" so 7zz reads the password from stdin instead of exposing it in CLI args (ps aux)
            args.append("-p")
            if encryptHeaders && format.supportsHeaderEncryption {
                args.append("-mhe=on")
            }
            effectivePassword = pwd
        } else {
            effectivePassword = nil
        }

        // Prevent packing the target archive into itself if it resides inside workingDirectory
        let archiveURL = URL(fileURLWithPath: archivePath).standardizedFileURL
        if let workDir = workingDirectory {
            let workDirURL = URL(fileURLWithPath: workDir, isDirectory: true).standardizedFileURL
            if archiveURL.deletingLastPathComponent() == workDirURL {
                args.append("-x!\(archiveURL.lastPathComponent)")
            }
        }

        args.append("--")
        args.append(archivePath)
        args.append(contentsOf: sourcePaths.map { Self.sanitizeRelativePathArgument($0) })

        let existedBefore = FileManager.default.fileExists(atPath: archivePath)

        do {
            let result = try runCommand(
                arguments: args,
                workingDirectory: workingDirectory,
                stdinPassword: effectivePassword,
                token: token
            )
            if result.exitCode != 0 {
                if !existedBefore {
                    try? FileManager.default.removeItem(atPath: archivePath)
                }
                let combined = result.stdout + "\n" + result.stderr
                throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combined))
            }
            return result.stdout
        } catch {
            if !existedBefore {
                try? FileManager.default.removeItem(atPath: archivePath)
            }
            throw error
        }
    }

    // MARK: - 3. Extract Archive (`7zz x` or `7zz e`)

    @discardableResult
    func extractArchive(
        archivePath: String,
        destinationPath: String,
        internalPaths: [String]? = nil,
        preserveDirectoryStructure: Bool = true,
        overwriteMode: ExtractOverwriteMode = .overwriteAll,
        password: String? = nil,
        token: SevenZipOperationToken? = nil
    ) throws -> String {
        // 1. Validate requested internalPaths against Zip Slip (".." or leading "/")
        if let paths = internalPaths {
            for p in paths {
                if !Self.isSafeArchiveEntryPath(p) {
                    throw SevenZipError.unsafeArchivePath(p)
                }
            }
        } else if let listing = try? listArchive(at: archivePath, password: password) {
            for entry in listing.entries {
                if !Self.isSafeArchiveEntryPath(entry.path) {
                    throw SevenZipError.unsafeArchivePath(entry.path)
                }
            }
        }

        // Read macOS com.apple.quarantine attribute from source archive before extraction
        let quarantineData = Self.readQuarantineAttribute(atPath: archivePath)

        let cmd = preserveDirectoryStructure ? "x" : "e"
        var args = [
            cmd,
            "-o\(destinationPath)",
            overwriteMode.rawValue,
            "-spd",
            "-y",
            "--",
            archivePath
        ]

        if let paths = internalPaths, !paths.isEmpty {
            args.append(contentsOf: paths)
        }

        let result = try runCommand(
            arguments: args,
            stdinPassword: password,
            token: token
        )
        if result.exitCode != 0 {
            let combined = result.stdout + "\n" + result.stderr
            if isPasswordError(in: combined, exitCode: result.exitCode) {
                throw SevenZipError.passwordRequired
            }
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combined))
        }

        // Propagate com.apple.quarantine to extracted files if the archive was quarantined
        if let qData = quarantineData {
            Self.propagateQuarantineAttribute(qData, toDirectory: destinationPath)
        }

        return result.stdout
    }

    // MARK: - 4. Test Archive (`7zz t`)

    func testArchive(
        archivePath: String,
        internalPaths: [String]? = nil,
        password: String? = nil,
        token: SevenZipOperationToken? = nil
    ) throws -> ArchiveTestResult {
        var args = ["t", "-spd", "-y", "--", archivePath]

        if let paths = internalPaths, !paths.isEmpty {
            args.append(contentsOf: paths)
        }

        let result = try runCommand(
            arguments: args,
            stdinPassword: password,
            token: token
        )
        let combined = (result.stdout + "\n" + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return ArchiveTestResult(
            isSuccess: result.exitCode == 0,
            archivePath: archivePath,
            output: combined
        )
    }

    // MARK: - 5. Delete from Archive (`7zz d`)

    @discardableResult
    func deleteFromArchive(
        archivePath: String,
        internalPaths: [String],
        password: String? = nil,
        token: SevenZipOperationToken? = nil
    ) throws -> String {
        var args = ["d", "-spd", "-y", "--", archivePath]
        args.append(contentsOf: internalPaths)

        let result = try runCommand(
            arguments: args,
            stdinPassword: password,
            token: token
        )
        if result.exitCode != 0 {
            let combined = result.stdout + "\n" + result.stderr
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combined))
        }
        return result.stdout
    }

    // MARK: - macOS Gatekeeper Quarantine Propagation

    private static let quarantineAttrName = "com.apple.quarantine"

    static func readQuarantineAttribute(atPath path: String) -> Data? {
        let size = getxattr(path, quarantineAttrName, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = Data(count: size)
        let readCount = buffer.withUnsafeMutableBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return getxattr(path, quarantineAttrName, base, size, 0, XATTR_NOFOLLOW)
        }
        guard readCount == size else { return nil }
        return buffer
    }

    static func propagateQuarantineAttribute(_ data: Data, toDirectory directoryPath: String) {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        guard let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: nil) else { return }

        for case let fileURL as URL in enumerator {
            data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                _ = setxattr(fileURL.path, quarantineAttrName, base, data.count, 0, XATTR_NOFOLLOW)
            }
        }
    }

    private func extractErrorMessage(from output: String) -> String {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let errorLines = lines.filter {
            $0.hasPrefix("ERROR:") ||
            $0.hasPrefix("System ERROR:") ||
            $0.localizedCaseInsensitiveContains("error") ||
            $0.localizedCaseInsensitiveContains("cannot")
        }
        if !errorLines.isEmpty {
            return errorLines.joined(separator: "\n")
        }
        return lines.suffix(5).joined(separator: "\n")
    }
}
