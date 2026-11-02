//
//  SevenZipEngine.swift
//  7-Zip GUI
//

import Foundation

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
    let path: String          // Internal path inside archive, normalized with "/" and no leading/trailing slash
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

enum SevenZipError: LocalizedError {
    case binaryNotFound
    case passwordRequired
    case commandFailed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "7-Zip engine binary (7zz) was not found in the application bundle."
        case .passwordRequired:
            return "This archive is encrypted and requires a password."
        case .commandFailed(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "7-Zip operation failed with exit code \(code)."
            }
            return trimmed
        }
    }
}

final class SevenZipEngine {
    static let shared = SevenZipEngine()

    static let supportedArchiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz2",
        "xz", "txz", "zst", "tzst", "wim", "iso", "dmg", "pkg",
        "xar", "cab", "arj", "cpio", "rpm", "deb", "lzma", "lzh",
        "vhd", "vhdx", "squashfs", "apfs"
    ]

    static func isArchiveFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedArchiveExtensions.contains(ext)
    }

    static func isModifiableArchive(path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["7z", "zip", "tar", "wim", "gz", "bz2", "xz"].contains(ext)
    }

    /// Resolves the path to the bundled `7zz` executable.
    func executableURL() throws -> URL {
        let fm = FileManager.default

        if let bundledURL = Bundle.main.url(forResource: "7zz", withExtension: nil),
           fm.fileExists(atPath: bundledURL.path) {
            ensureExecutablePermission(at: bundledURL)
            return bundledURL
        }

        // Also check Bundle(for: SevenZipEngine.self) when running unit tests
        let classBundle = Bundle(for: SevenZipEngine.self)
        if let testBundledURL = classBundle.url(forResource: "7zz", withExtension: nil),
           fm.fileExists(atPath: testBundledURL.path) {
            ensureExecutablePermission(at: testBundledURL)
            return testBundledURL
        }

        // Fallback relative to source file for unit tests
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

    // MARK: - Core Process Runner

    @discardableResult
    func runCommand(arguments: [String], workingDirectory: String? = nil) throws -> (exitCode: Int32, stdout: String, stderr: String) {
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
        process.standardInput = FileHandle.nullDevice

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
        process.waitUntilExit()
        group.wait()

        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? String(decoding: stdoutData, as: UTF8.self)
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? String(decoding: stderrData, as: UTF8.self)

        return (process.terminationStatus, stdoutStr, stderrStr)
    }

    // MARK: - 1. List Archive (`7zz l -slt`)

    func listArchive(at archivePath: String, password: String? = nil) throws -> ArchiveListing {
        var args = ["l", "-slt", "-y"]
        if let pwd = password, !pwd.isEmpty {
            args.append("-p\(pwd)")
        } else {
            args.append("-p")
        }
        args.append(archivePath)

        let result = try runCommand(arguments: args)
        let combinedOutput = result.stdout + "\n" + result.stderr

        if result.exitCode != 0 {
            if combinedOutput.localizedCaseInsensitiveContains("Wrong password") ||
               combinedOutput.localizedCaseInsensitiveContains("Can not open encrypted archive") {
                throw SevenZipError.passwordRequired
            }
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combinedOutput))
        }

        return Self.parseTechnicalListing(result.stdout, archivePath: archivePath)
    }

    static func parseTechnicalListing(_ output: String, archivePath: String) -> ArchiveListing {
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n----------\n")

        var archiveType = URL(fileURLWithPath: archivePath).pathExtension
        var physicalSize: UInt64 = 0
        var headersSize: UInt64 = 0
        var archiveMethod = ""
        var isSolid = false

        // Parse header section (after "--")
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
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { continue }

            var dict: [String: String] = [:]
            for line in lines {
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
                dict[key] = val
            }

            guard let rawPath = dict["Path"], !rawPath.isEmpty else { continue }
            let normalizedPath = rawPath
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !normalizedPath.isEmpty else { continue }

            let folderFlag = dict["Folder"]
            let attr = dict["Attributes"] ?? ""
            let isDir = (folderFlag == "+") || attr.hasPrefix("D") || attr.contains("d") && attr.hasPrefix("D") || rawPath.hasSuffix("/")
            let size = UInt64(dict["Size"] ?? "") ?? 0
            let packedSize = UInt64(dict["Packed Size"] ?? "") ?? 0
            let modified = parse7ZipDate(dict["Modified"])
            let created = parse7ZipDate(dict["Created"])
            let accessed = parse7ZipDate(dict["Accessed"])
            let crc = dict["CRC"] ?? ""
            let encrypted = (dict["Encrypted"] == "+")
            let method = dict["Method"] ?? ""
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
        // Trim fractional seconds if present: "2026-11-01 19:39:14.5431139" -> "2026-11-01 19:39:14"
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
        workingDirectory: String? = nil
    ) throws -> String {
        var args = [
            "a",
            "-t\(format.rawValue)",
            "-mx=\(level.rawValue)",
            "-y"
        ]

        if format == .sevenZ && level != .store {
            args.append(solid ? "-ms=on" : "-ms=off")
        }

        if let pwd = password, !pwd.isEmpty, format.supportsEncryption {
            args.append("-p\(pwd)")
            if encryptHeaders && format.supportsHeaderEncryption {
                args.append("-mhe=on")
            }
        }

        args.append(archivePath)
        args.append("--")
        args.append(contentsOf: sourcePaths)

        let result = try runCommand(arguments: args, workingDirectory: workingDirectory)
        if result.exitCode != 0 {
            let combined = result.stdout + "\n" + result.stderr
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combined))
        }
        return result.stdout
    }

    // MARK: - 3. Extract Archive (`7zz x` or `7zz e`)

    @discardableResult
    func extractArchive(
        archivePath: String,
        destinationPath: String,
        internalPaths: [String]? = nil,
        preserveDirectoryStructure: Bool = true,
        overwriteMode: ExtractOverwriteMode = .overwriteAll,
        password: String? = nil
    ) throws -> String {
        let cmd = preserveDirectoryStructure ? "x" : "e"
        var args = [
            cmd,
            archivePath,
            "-o\(destinationPath)",
            overwriteMode.rawValue,
            "-y"
        ]

        if let pwd = password, !pwd.isEmpty {
            args.append("-p\(pwd)")
        } else {
            args.append("-p")
        }

        if let paths = internalPaths, !paths.isEmpty {
            args.append("--")
            args.append(contentsOf: paths)
        }

        let result = try runCommand(arguments: args)
        if result.exitCode != 0 {
            let combined = result.stdout + "\n" + result.stderr
            if combined.localizedCaseInsensitiveContains("Wrong password") ||
               combined.localizedCaseInsensitiveContains("Data Error in encrypted file") {
                throw SevenZipError.passwordRequired
            }
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combined))
        }
        return result.stdout
    }

    // MARK: - 4. Test Archive (`7zz t`)

    func testArchive(
        archivePath: String,
        internalPaths: [String]? = nil,
        password: String? = nil
    ) throws -> ArchiveTestResult {
        var args = ["t", archivePath, "-y"]
        if let pwd = password, !pwd.isEmpty {
            args.append("-p\(pwd)")
        } else {
            args.append("-p")
        }

        if let paths = internalPaths, !paths.isEmpty {
            args.append("--")
            args.append(contentsOf: paths)
        }

        let result = try runCommand(arguments: args)
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
        password: String? = nil
    ) throws -> String {
        var args = ["d", archivePath, "-y"]
        if let pwd = password, !pwd.isEmpty {
            args.append("-p\(pwd)")
        }
        args.append("--")
        args.append(contentsOf: internalPaths)

        let result = try runCommand(arguments: args)
        if result.exitCode != 0 {
            let combined = result.stdout + "\n" + result.stderr
            throw SevenZipError.commandFailed(exitCode: result.exitCode, message: extractErrorMessage(from: combined))
        }
        return result.stdout
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
