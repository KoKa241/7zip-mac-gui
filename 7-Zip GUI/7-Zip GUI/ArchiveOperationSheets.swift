//
//  ArchiveOperationSheets.swift
//  7-Zip GUI
//

import SwiftUI
import AppKit

// MARK: - 1. Add to Archive Sheet

struct AddArchiveSheet: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    let sourceDirectory: String
    let sourceItems: [FileItem]
    @Binding var isPresented: Bool

    @State private var archivePath: String = ""
    @State private var format: ArchiveFormat = .sevenZ
    @State private var compressionLevel: CompressionLevel = .normal
    @State private var isSolid: Bool = true
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var encryptHeaders: Bool = false
    @State private var isRunning: Bool = false
    @State private var errorMessage: String? = nil

    init(
        appViewModel: FileManagerAppViewModel,
        sourceDirectory: String,
        sourceItems: [FileItem],
        isPresented: Binding<Bool>
    ) {
        self.appViewModel = appViewModel
        self.sourceDirectory = sourceDirectory
        self.sourceItems = sourceItems
        self._isPresented = isPresented

        let baseName: String
        if sourceItems.count == 1, let single = sourceItems.first {
            baseName = single.isDirectory
                ? single.name
                : (single.name as NSString).deletingPathExtension
        } else {
            let folderName = URL(fileURLWithPath: sourceDirectory).lastPathComponent
            baseName = folderName.isEmpty || folderName == "/" ? "archive" : folderName
        }

        let initialPath = (sourceDirectory as NSString).appendingPathComponent("\(baseName).7z")
        self._archivePath = State(initialValue: initialPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add to Archive")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(sourceItems.count) item(s) selected in \(sourceDirectory)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Divider()

            // Archive Path
            VStack(alignment: .leading, spacing: 4) {
                Text("Archive:")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    TextField("Archive path", text: $archivePath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("...") {
                        browseSavePath()
                    }
                    .frame(width: 34)
                }
            }

            // Format & Compression Level
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Archive format:")
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: Binding(
                        get: { format },
                        set: { newFormat in
                            format = newFormat
                            updateExtension(for: newFormat)
                        }
                    )) {
                        ForEach(ArchiveFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)

                    Text("Compression level:")
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: $compressionLevel) {
                        ForEach(CompressionLevel.allCases) { lvl in
                            Text(lvl.displayName).tag(lvl)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)

                    if format == .sevenZ {
                        Toggle("Solid archive", isOn: $isSolid)
                            .font(.system(size: 12))
                            .disabled(compressionLevel == .store)
                    }
                }

                Divider()

                // Encryption
                VStack(alignment: .leading, spacing: 8) {
                    Text("Encryption:")
                        .font(.system(size: 12, weight: .medium))

                    if format.supportsEncryption {
                        Text("Enter password (optional):")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if showPassword {
                            TextField("Password", text: $password)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            SecureField("Password", text: $password)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        Toggle("Show password", isOn: $showPassword)
                            .font(.system(size: 12))

                        if format.supportsHeaderEncryption {
                            Toggle("Encrypt file names", isOn: $encryptHeaders)
                                .font(.system(size: 12))
                                .disabled(password.isEmpty)
                        }
                    } else {
                        Text("Encryption is not supported for \(format.displayName) format.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Divider()

            HStack {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Creating archive...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isRunning)

                Button("OK") {
                    startCompression()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || archivePath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 500, height: 340)
    }

    private func updateExtension(for newFormat: ArchiveFormat) {
        let current = archivePath.trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty else { return }
        let withoutExt = (current as NSString).deletingPathExtension
        archivePath = "\(withoutExt).\(newFormat.fileExtension)"
    }

    private func browseSavePath() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Archive As"
        savePanel.nameFieldStringValue = URL(fileURLWithPath: archivePath).lastPathComponent
        savePanel.directoryURL = URL(fileURLWithPath: sourceDirectory)
        if savePanel.runModal() == .OK, let url = savePanel.url {
            archivePath = url.path
        }
    }

    private func startCompression() {
        errorMessage = nil
        isRunning = true

        let targetArchive = (archivePath as NSString).expandingTildeInPath
        let fmt = format
        let lvl = compressionLevel
        let solid = isSolid
        let pwd = password.isEmpty ? nil : password
        let encHeaders = encryptHeaders
        let relativeNames = sourceItems.map { $0.name }
        let workDir = sourceDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try SevenZipEngine.shared.createArchive(
                    archivePath: targetArchive,
                    format: fmt,
                    level: lvl,
                    solid: solid,
                    password: pwd,
                    encryptHeaders: encHeaders,
                    sourcePaths: relativeNames,
                    workingDirectory: workDir
                )
                DispatchQueue.main.async {
                    isRunning = false
                    isPresented = false
                    appViewModel.refreshPanels()
                }
            } catch {
                DispatchQueue.main.async {
                    isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 2. Extract Archive Sheet

struct ExtractArchiveSheet: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    let archivePath: String
    let internalPaths: [String]?
    let initialPassword: String?
    @Binding var isPresented: Bool

    @State private var destinationPath: String
    @State private var preserveDirectoryStructure: Bool = true
    @State private var overwriteMode: ExtractOverwriteMode = .overwriteAll
    @State private var password: String
    @State private var showPassword: Bool = false
    @State private var isRunning: Bool = false
    @State private var errorMessage: String? = nil

    init(
        appViewModel: FileManagerAppViewModel,
        archivePath: String,
        internalPaths: [String]?,
        defaultDestination: String,
        initialPassword: String?,
        isPresented: Binding<Bool>
    ) {
        self.appViewModel = appViewModel
        self.archivePath = archivePath
        self.internalPaths = internalPaths
        self.initialPassword = initialPassword
        self._isPresented = isPresented
        self._destinationPath = State(initialValue: defaultDestination)
        self._password = State(initialValue: initialPassword ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extract Archive")
                        .font(.system(size: 16, weight: .semibold))
                    Text(summarySubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Extract to:")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    TextField("Destination folder", text: $destinationPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("...") {
                        browseDestination()
                    }
                    .frame(width: 34)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overwrite mode:")
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: $overwriteMode) {
                        ForEach(ExtractOverwriteMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Toggle("Preserve directory structure", isOn: $preserveDirectoryStructure)
                        .font(.system(size: 12))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password (if encrypted):")
                        .font(.system(size: 12, weight: .medium))

                    if showPassword {
                        TextField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    Toggle("Show password", isOn: $showPassword)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Divider()

            HStack {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Extracting...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isRunning)

                Button("OK") {
                    startExtraction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || destinationPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 500, height: 300)
    }

    private var summarySubtitle: String {
        let name = URL(fileURLWithPath: archivePath).lastPathComponent
        if let paths = internalPaths, !paths.isEmpty {
            return "Extracting \(paths.count) selected item(s) from \(name)"
        }
        return "Archive: \(name)"
    }

    private func browseDestination() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Destination Folder"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.directoryURL = URL(fileURLWithPath: destinationPath)
        if openPanel.runModal() == .OK, let url = openPanel.url {
            destinationPath = url.path
        }
    }

    private func startExtraction() {
        errorMessage = nil
        isRunning = true

        let dest = (destinationPath as NSString).expandingTildeInPath
        let arch = archivePath
        let paths = internalPaths
        let preserve = preserveDirectoryStructure
        let overwrite = overwriteMode
        let pwd = password.isEmpty ? nil : password

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: dest, isDirectory: true),
                    withIntermediateDirectories: true
                )
                try SevenZipEngine.shared.extractArchive(
                    archivePath: arch,
                    destinationPath: dest,
                    internalPaths: paths,
                    preserveDirectoryStructure: preserve,
                    overwriteMode: overwrite,
                    password: pwd
                )
                DispatchQueue.main.async {
                    isRunning = false
                    isPresented = false
                    appViewModel.refreshPanels()
                }
            } catch {
                DispatchQueue.main.async {
                    isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 3. Copy / Move Sheet

enum CopyMoveOperationType {
    case copy
    case move

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }

    var iconName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "folder.badge.gearshape"
        }
    }
}

struct CopyMoveSheet: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel
    let operation: CopyMoveOperationType
    let sourceItems: [FileItem]
    let sourceArchivePath: String?
    let sourceArchivePassword: String?
    @Binding var isPresented: Bool

    @State private var destinationPath: String
    @State private var isRunning: Bool = false
    @State private var errorMessage: String? = nil

    init(
        appViewModel: FileManagerAppViewModel,
        operation: CopyMoveOperationType,
        sourceItems: [FileItem],
        sourceArchivePath: String?,
        sourceArchivePassword: String?,
        defaultDestination: String,
        isPresented: Binding<Bool>
    ) {
        self.appViewModel = appViewModel
        self.operation = operation
        self.sourceItems = sourceItems
        self.sourceArchivePath = sourceArchivePath
        self.sourceArchivePassword = sourceArchivePassword
        self._isPresented = isPresented
        self._destinationPath = State(initialValue: defaultDestination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(operation.title) \(sourceItems.count) item(s) to destination folder:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("\(operation.title) to:")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    TextField("Destination folder", text: $destinationPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("...") {
                        browseDestination()
                    }
                    .frame(width: 34)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Items:")
                    .font(.system(size: 12, weight: .medium))
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(sourceItems.prefix(20)) { item in
                            HStack(spacing: 6) {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                Text(item.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if sourceItems.count > 20 {
                            Text("... and \(sourceItems.count - 20) more item(s)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 85)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Divider()

            HStack {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Working...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isRunning)

                Button("OK") {
                    performOperation()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || destinationPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460, height: 300)
    }

    private func browseDestination() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Destination Folder"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.directoryURL = URL(fileURLWithPath: destinationPath)
        if openPanel.runModal() == .OK, let url = openPanel.url {
            destinationPath = url.path
        }
    }

    private func performOperation() {
        errorMessage = nil
        isRunning = true

        let destDir = (destinationPath as NSString).expandingTildeInPath
        let op = operation
        let items = sourceItems
        let archPath = sourceArchivePath
        let archPwd = sourceArchivePassword

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: destDir, isDirectory: true),
                    withIntermediateDirectories: true
                )

                if let archivePath = archPath {
                    let internalPaths = items.compactMap { $0.archiveInternalPath }
                    try SevenZipEngine.shared.extractArchive(
                        archivePath: archivePath,
                        destinationPath: destDir,
                        internalPaths: internalPaths.isEmpty ? nil : internalPaths,
                        preserveDirectoryStructure: true,
                        overwriteMode: .overwriteAll,
                        password: archPwd
                    )
                    if op == .move && SevenZipEngine.isModifiableArchive(path: archivePath) && !internalPaths.isEmpty {
                        try SevenZipEngine.shared.deleteFromArchive(
                            archivePath: archivePath,
                            internalPaths: internalPaths,
                            password: archPwd
                        )
                    }
                } else {
                    try appViewModel.performFilesystemCopyMove(
                        items: items,
                        toDirectory: destDir,
                        isMove: op == .move
                    )
                }

                DispatchQueue.main.async {
                    isRunning = false
                    isPresented = false
                    appViewModel.refreshPanels()
                }
            } catch {
                DispatchQueue.main.async {
                    isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
