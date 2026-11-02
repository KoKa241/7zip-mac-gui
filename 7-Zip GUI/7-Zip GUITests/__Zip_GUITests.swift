//
//  __Zip_GUITests.swift
//  7-Zip GUITests
//
//  Created by Vlad on 01.11.2026.
//

import XCTest
import AppKit
import SwiftUI
@testable import __Zip_GUI

final class __Zip_GUITests: XCTestCase {

    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let baseTemp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        tempDirectoryURL = baseTemp.appendingPathComponent("7ZipGUITests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. FileItem Formatting & Equatable Tests

    func test7ZipNumberFormatting() {
        XCTAssertEqual(FileItem.format7ZipNumber(0), "0")
        XCTAssertEqual(FileItem.format7ZipNumber(999), "999")
        XCTAssertEqual(FileItem.format7ZipNumber(1_000), "1 000")
        XCTAssertEqual(FileItem.format7ZipNumber(1_234_567), "1 234 567")
    }

    func testPosixPermissionsFormatting() {
        XCTAssertEqual(FilePanelViewModel.formatPosixPermissions(0o755, isDirectory: true, isSymlink: false), "drwxr-xr-x")
        XCTAssertEqual(FilePanelViewModel.formatPosixPermissions(0o644, isDirectory: false, isSymlink: false), "-rw-r--r--")
        XCTAssertEqual(FilePanelViewModel.formatPosixPermissions(0o777, isDirectory: false, isSymlink: true), "lrwxrwxrwx")
        XCTAssertEqual(FilePanelViewModel.formatPosixPermissions(0o000, isDirectory: false, isSymlink: false), "----------")
    }

    func testFileItemEqualityDetectsMetadataChanges() {
        let url = tempDirectoryURL.appendingPathComponent("sample.txt")
        let icon = NSImage()
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = Date(timeIntervalSince1970: 1_700_000_500)

        let item1 = FileItem(
            id: url.path,
            url: url,
            name: "sample.txt",
            isDirectory: false,
            isParentEntry: false,
            size: 100,
            packedSize: 4096,
            modifiedDate: date1,
            createdDate: date1,
            accessedDate: date1,
            posixPermissions: "-rw-r--r--",
            fileType: "Text",
            comment: "",
            icon: icon
        )

        let item2 = FileItem(
            id: url.path,
            url: url,
            name: "sample.txt",
            isDirectory: false,
            isParentEntry: false,
            size: 250,
            packedSize: 4096,
            modifiedDate: date2,
            createdDate: date1,
            accessedDate: date1,
            posixPermissions: "-rw-r--r--",
            fileType: "Text",
            comment: "",
            icon: icon
        )

        XCTAssertNotEqual(item1, item2, "FileItem equality must detect size and modification date changes")
    }

    // MARK: - 2. FilePanelViewModel Directory Loading & Navigation Tests

    func testDirectoryLoadingAndParentEntry() throws {
        let subFolder = tempDirectoryURL.appendingPathComponent("SubFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)

        let fileA = tempDirectoryURL.appendingPathComponent("alpha.txt")
        let fileB = tempDirectoryURL.appendingPathComponent("beta.log")
        try Data("hello".utf8).write(to: fileA)
        try Data(repeating: 0x41, count: 1024).write(to: fileB)

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: tempDirectoryURL.path)

        // First item must be ".."
        XCTAssertEqual(vm.items.first?.isParentEntry, true)
        XCTAssertEqual(vm.items.first?.name, "..")

        // Total objects excludes ".."
        XCTAssertEqual(vm.totalObjectCount, 3)

        // Directories are grouped before files
        let nonParentItems = vm.items.filter { !$0.isParentEntry }
        XCTAssertEqual(nonParentItems.first?.name, "SubFolder")
        XCTAssertEqual(nonParentItems.first?.isDirectory, true)
    }

    func testNavigationUpAndInvalidPathRecovery() throws {
        let subFolder = tempDirectoryURL.appendingPathComponent("ChildDir", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: subFolder.path)
        XCTAssertTrue(vm.canGoUp)
        XCTAssertTrue(vm.pathInput.hasSuffix("/"))

        // Navigate up to tempDirectoryURL
        vm.navigateUp()
        XCTAssertEqual(vm.currentPath, tempDirectoryURL.standardizedFileURL.path)

        // Attempt navigating to non-existent folder
        let nonExistent = tempDirectoryURL.appendingPathComponent("DoesNotExist").path
        vm.navigateTo(path: nonExistent)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.currentPath, tempDirectoryURL.standardizedFileURL.path)
        XCTAssertTrue(vm.pathInput.hasSuffix("/"), "pathInput should restore trailing slash on invalid path")
    }

    func testHiddenFilesToggle() throws {
        let hiddenFile = tempDirectoryURL.appendingPathComponent(".secret")
        let visibleFile = tempDirectoryURL.appendingPathComponent("visible.txt")
        try Data("secret".utf8).write(to: hiddenFile)
        try Data("visible".utf8).write(to: visibleFile)

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: tempDirectoryURL.path)
        vm.showHiddenFiles = false
        vm.refresh()
        XCTAssertEqual(vm.totalObjectCount, 1)

        vm.showHiddenFiles = true
        vm.refresh()
        XCTAssertEqual(vm.totalObjectCount, 2)
    }

    func testFlatViewEnumeratesNestedFiles() throws {
        let nestedDir = tempDirectoryURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let nestedFile = nestedDir.appendingPathComponent("deep.txt")
        try Data("deep".utf8).write(to: nestedFile)

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: tempDirectoryURL.path)
        vm.flatView = false
        vm.refresh()
        XCTAssertEqual(vm.totalObjectCount, 1) // Only "Nested" folder

        vm.flatView = true
        vm.refresh()
        XCTAssertEqual(vm.totalObjectCount, 2) // "Nested" and "Nested/deep.txt"
        XCTAssertTrue(vm.items.contains { $0.name == "Nested/deep.txt" })
    }

    // MARK: - 3. Sorting Tests

    func testSortingByNameAndSizeKeepsFoldersFirst() throws {
        let folderZ = tempDirectoryURL.appendingPathComponent("Z_Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderZ, withIntermediateDirectories: true)

        let smallFile = tempDirectoryURL.appendingPathComponent("a_small.bin")
        let largeFile = tempDirectoryURL.appendingPathComponent("b_large.bin")
        try Data(repeating: 1, count: 10).write(to: smallFile)
        try Data(repeating: 2, count: 5000).write(to: largeFile)

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: tempDirectoryURL.path)

        // Sort by size descending
        vm.setSort(column: .size, ascending: false)
        let regular = vm.items.filter { !$0.isParentEntry }
        XCTAssertEqual(regular.map { $0.name }, ["Z_Folder", "b_large.bin", "a_small.bin"])

        // Sort by size ascending
        vm.setSort(column: .size, ascending: true)
        let regularAsc = vm.items.filter { !$0.isParentEntry }
        XCTAssertEqual(regularAsc.map { $0.name }, ["Z_Folder", "a_small.bin", "b_large.bin"])
    }

    // MARK: - 4. Selection & Status Bar Metrics Tests

    func testSelectionAndStatusBarMetrics() throws {
        let file1 = tempDirectoryURL.appendingPathComponent("one.bin")
        let file2 = tempDirectoryURL.appendingPathComponent("two.bin")
        try Data(repeating: 0xAA, count: 1200).write(to: file1)
        try Data(repeating: 0xBB, count: 800).write(to: file2)

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: tempDirectoryURL.path)
        XCTAssertEqual(vm.statusObjectsText, "0 / 2 object(s) selected")
        XCTAssertEqual(vm.statusSelectedSizeText, "")

        // Select All
        vm.selectAll()
        XCTAssertEqual(vm.selectedObjectCount, 2)
        XCTAssertEqual(vm.statusObjectsText, "2 / 2 object(s) selected")
        XCTAssertEqual(vm.statusSelectedSizeText, "2 000")
        XCTAssertNotNil(vm.focusedItem)

        // Invert Selection
        vm.invertSelection()
        XCTAssertEqual(vm.selectedObjectCount, 0)
        XCTAssertNil(vm.focusedItem)

        // Select one item and invert
        let firstRegular = try XCTUnwrap(vm.items.first { !$0.isParentEntry })
        vm.updateSelection(ids: [firstRegular.id], focused: firstRegular)
        vm.invertSelection()
        XCTAssertEqual(vm.selectedObjectCount, 1)
        XCTAssertFalse(vm.selectedIDs.contains(firstRegular.id))

        // Deselect All
        vm.deselectAll()
        XCTAssertEqual(vm.selectedObjectCount, 0)
        XCTAssertNil(vm.focusedItem)
    }

    // MARK: - 5. App ViewModel & Toolbar Asset Tests

    func testDualPaneSwitchingAndToolbarAssetsExist() {
        let appVM = FileManagerAppViewModel()
        XCTAssertFalse(appVM.isDualPane)
        XCTAssertEqual(appVM.activePanelIndex, 0)

        appVM.toggleDualPane()
        XCTAssertTrue(appVM.isDualPane)

        appVM.rightPanel.onActivatePanel?()
        XCTAssertEqual(appVM.activePanelIndex, 1)
        XCTAssertTrue(appVM.activePanel === appVM.rightPanel)
        XCTAssertTrue(appVM.targetPanel === appVM.leftPanel)

        appVM.toggleDualPane()
        XCTAssertFalse(appVM.isDualPane)
        XCTAssertEqual(appVM.activePanelIndex, 0)

        // Verify all 14 converted 7-Zip toolbar icons load from the asset catalog
        let assetNames = [
            "Toolbar_Add", "Toolbar_Extract", "Toolbar_Test",
            "Toolbar_Copy", "Toolbar_Move", "Toolbar_Delete", "Toolbar_Info",
            "Toolbar_Add2", "Toolbar_Extract2", "Toolbar_Test2",
            "Toolbar_Copy2", "Toolbar_Move2", "Toolbar_Delete2", "Toolbar_Info2"
        ]
        for name in assetNames {
            XCTAssertNotNil(NSImage(named: name), "Missing toolbar icon asset: \(name)")
        }
    }

    func testContentViewAndFileTableViewHierarchy() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("test_row.txt")
        try Data("row content".utf8).write(to: fileURL)

        let appVM = FileManagerAppViewModel()
        appVM.leftPanel.navigateTo(path: tempDirectoryURL.path)

        let hostingController = NSHostingController(rootView: ContentView(appViewModel: appVM))
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        hostingController.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(appVM.leftPanel.totalObjectCount, 1)
        XCTAssertEqual(appVM.leftPanel.items.count, 2) // ".." + "test_row.txt"

        // Switch to 2 Panels and verify layout updates cleanly
        appVM.toggleDualPane()
        hostingController.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(appVM.isDualPane)
    }

    func testThemeAndToolbarIconStyleSwitching() {
        let appVM = FileManagerAppViewModel()

        // Test Theme switching (System / Light / Dark)
        appVM.appTheme = .dark
        XCTAssertEqual(appVM.appTheme, .dark)
        XCTAssertEqual(appVM.appTheme.preferredColorScheme, .dark)

        appVM.appTheme = .light
        XCTAssertEqual(appVM.appTheme, .light)
        XCTAssertEqual(appVM.appTheme.preferredColorScheme, .light)

        appVM.appTheme = .system
        XCTAssertNil(appVM.appTheme.preferredColorScheme)

        // Test Toolbar Icon Style switching (Modern / Classic)
        appVM.toolbarIconStyle = .modern
        XCTAssertEqual(appVM.toolbarIconStyle, .modern)

        appVM.toolbarIconStyle = .classic
        XCTAssertEqual(appVM.toolbarIconStyle, .classic)

        // Reset back to modern default
        appVM.toolbarIconStyle = .modern
    }

    // MARK: - 6. 7-Zip Engine Integration & Archive Browsing Tests

    func testSevenZipEngineCreateListTestAndExtract7zArchive() throws {
        let srcDir = tempDirectoryURL.appendingPathComponent("src", isDirectory: true)
        let subDir = srcDir.appendingPathComponent("SubDir", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let rootFile = srcDir.appendingPathComponent("root.txt")
        let nestedFile = subDir.appendingPathComponent("nested.txt")
        try Data("Hello from 7-Zip root!".utf8).write(to: rootFile)
        try Data("Nested file content 12345".utf8).write(to: nestedFile)

        let archiveURL = tempDirectoryURL.appendingPathComponent("test_bundle.7z")

        // 1. Create .7z archive
        try SevenZipEngine.shared.createArchive(
            archivePath: archiveURL.path,
            format: .sevenZ,
            level: .normal,
            solid: true,
            sourcePaths: ["root.txt", "SubDir"],
            workingDirectory: srcDir.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        // 2. Test archive integrity
        let testResult = try SevenZipEngine.shared.testArchive(archivePath: archiveURL.path)
        XCTAssertTrue(testResult.isSuccess)
        XCTAssertTrue(testResult.output.contains("Everything is Ok"))

        // 3. List archive contents
        let listing = try SevenZipEngine.shared.listArchive(at: archiveURL.path)
        XCTAssertEqual(listing.archiveType, "7z")
        XCTAssertTrue(listing.entries.contains { $0.path == "root.txt" && $0.size == 22 })
        XCTAssertTrue(listing.entries.contains { $0.path == "SubDir/nested.txt" && $0.size == 25 })

        // 4. Extract archive to destination directory
        let outDir = tempDirectoryURL.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try SevenZipEngine.shared.extractArchive(
            archivePath: archiveURL.path,
            destinationPath: outDir.path
        )

        let extractedRoot = try String(contentsOf: outDir.appendingPathComponent("root.txt"), encoding: .utf8)
        let extractedNested = try String(contentsOf: outDir.appendingPathComponent("SubDir/nested.txt"), encoding: .utf8)
        XCTAssertEqual(extractedRoot, "Hello from 7-Zip root!")
        XCTAssertEqual(extractedNested, "Nested file content 12345")
    }

    func testSevenZipEngineEncryptedArchiveWithPassword() throws {
        let secretFile = tempDirectoryURL.appendingPathComponent("secret.txt")
        try Data("Top secret payload".utf8).write(to: secretFile)

        let archiveURL = tempDirectoryURL.appendingPathComponent("encrypted.7z")
        try SevenZipEngine.shared.createArchive(
            archivePath: archiveURL.path,
            format: .sevenZ,
            level: .fast,
            password: "MySecretPassword123",
            encryptHeaders: true,
            sourcePaths: ["secret.txt"],
            workingDirectory: tempDirectoryURL.path
        )

        // Listing without password should throw passwordRequired
        XCTAssertThrowsError(try SevenZipEngine.shared.listArchive(at: archiveURL.path)) { error in
            guard case SevenZipError.passwordRequired = error else {
                XCTFail("Expected passwordRequired, got \(error)")
                return
            }
        }

        // Listing with correct password succeeds
        let listing = try SevenZipEngine.shared.listArchive(at: archiveURL.path, password: "MySecretPassword123")
        XCTAssertEqual(listing.entries.count, 1)
        XCTAssertEqual(listing.entries.first?.path, "secret.txt")
    }

    func testBrowsingInsideArchiveAndNavigatingUp() throws {
        let srcDir = tempDirectoryURL.appendingPathComponent("zip_src", isDirectory: true)
        let folderA = srcDir.appendingPathComponent("FolderA", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try Data("top".utf8).write(to: srcDir.appendingPathComponent("top.txt"))
        try Data("inside".utf8).write(to: folderA.appendingPathComponent("inside.txt"))

        let zipURL = tempDirectoryURL.appendingPathComponent("browse.zip")
        try SevenZipEngine.shared.createArchive(
            archivePath: zipURL.path,
            format: .zip,
            level: .normal,
            sourcePaths: ["top.txt", "FolderA"],
            workingDirectory: srcDir.path
        )

        let vm = FilePanelViewModel(panelIndex: 0, initialPath: tempDirectoryURL.path)
        XCTAssertFalse(vm.isInsideArchive)

        // Open browse.zip in panel
        let zipItem = try XCTUnwrap(vm.items.first { $0.name == "browse.zip" })
        vm.openItem(zipItem)

        XCTAssertTrue(vm.isInsideArchive)
        XCTAssertEqual(vm.currentArchivePath, zipURL.path)
        XCTAssertEqual(vm.archiveInternalPrefix, "")
        XCTAssertEqual(vm.totalObjectCount, 2) // FolderA and top.txt

        // Enter FolderA inside the archive
        let folderAItem = try XCTUnwrap(vm.items.first { $0.name == "FolderA" && $0.isDirectory })
        vm.openItem(folderAItem)

        XCTAssertTrue(vm.isInsideArchive)
        XCTAssertEqual(vm.archiveInternalPrefix, "FolderA/")
        XCTAssertEqual(vm.totalObjectCount, 1)
        XCTAssertEqual(vm.items.first { !$0.isParentEntry }?.name, "inside.txt")

        // Navigate up once -> back to root of archive
        vm.navigateUp()
        XCTAssertTrue(vm.isInsideArchive)
        XCTAssertEqual(vm.archiveInternalPrefix, "")

        // Navigate up again -> exits archive back to tempDirectoryURL
        vm.navigateUp()
        XCTAssertFalse(vm.isInsideArchive)
        XCTAssertNil(vm.currentArchivePath)
        XCTAssertEqual(vm.currentPath, tempDirectoryURL.standardizedFileURL.path)
    }

    func testDeleteFromArchiveAndFilesystemCopyMove() throws {
        let f1 = tempDirectoryURL.appendingPathComponent("keep.txt")
        let f2 = tempDirectoryURL.appendingPathComponent("remove.txt")
        try Data("keep".utf8).write(to: f1)
        try Data("remove".utf8).write(to: f2)

        let archiveURL = tempDirectoryURL.appendingPathComponent("modifiable.7z")
        try SevenZipEngine.shared.createArchive(
            archivePath: archiveURL.path,
            format: .sevenZ,
            level: .fast,
            sourcePaths: ["keep.txt", "remove.txt"],
            workingDirectory: tempDirectoryURL.path
        )

        try SevenZipEngine.shared.deleteFromArchive(
            archivePath: archiveURL.path,
            internalPaths: ["remove.txt"]
        )

        let listing = try SevenZipEngine.shared.listArchive(at: archiveURL.path)
        XCTAssertEqual(listing.entries.map { $0.path }, ["keep.txt"])

        // Test filesystem Copy & Move via FileManagerAppViewModel
        let appVM = FileManagerAppViewModel()
        let destDir = tempDirectoryURL.appendingPathComponent("dest_panel", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        appVM.leftPanel.navigateTo(path: tempDirectoryURL.path)
        let keepItem = try XCTUnwrap(appVM.leftPanel.items.first { $0.name == "keep.txt" })

        try appVM.performFilesystemCopyMove(items: [keepItem], toDirectory: destDir.path, isMove: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("keep.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f1.path))

        let removeItem = try XCTUnwrap(appVM.leftPanel.items.first { $0.name == "remove.txt" })
        try appVM.performFilesystemCopyMove(items: [removeItem], toDirectory: destDir.path, isMove: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("remove.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f2.path))
    }

    func testToolbarActionsPresentModalSheets() throws {
        let sampleFile = tempDirectoryURL.appendingPathComponent("doc.txt")
        try Data("hello".utf8).write(to: sampleFile)

        let archiveURL = tempDirectoryURL.appendingPathComponent("sample.7z")
        try SevenZipEngine.shared.createArchive(
            archivePath: archiveURL.path,
            format: .sevenZ,
            level: .fast,
            sourcePaths: ["doc.txt"],
            workingDirectory: tempDirectoryURL.path
        )

        let appVM = FileManagerAppViewModel()
        appVM.leftPanel.navigateTo(path: tempDirectoryURL.path)

        // 1. Add button works even without explicit selection (selects folder items)
        appVM.actionAdd()
        if case .addArchive(let dir, let items) = appVM.activeModalSheet {
            XCTAssertEqual(dir, tempDirectoryURL.standardizedFileURL.path)
            XCTAssertEqual(items.count, 2)
        } else {
            XCTFail("Expected .addArchive modal sheet")
        }
        appVM.activeModalSheet = nil

        // 2. Extract button automatically finds sample.7z in current folder
        appVM.actionExtract()
        if case .extractArchive(let path, _, _, _) = appVM.activeModalSheet {
            XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL, archiveURL.standardizedFileURL)
        } else {
            XCTFail("Expected .extractArchive modal sheet")
        }
        appVM.activeModalSheet = nil

        // 3. Select doc.txt and test Copy, Move, Info
        let docItem = try XCTUnwrap(appVM.leftPanel.items.first { $0.name == "doc.txt" })
        appVM.leftPanel.updateSelection(ids: [docItem.id], focused: docItem)

        appVM.actionCopy()
        if case .copyMove(let op, let items, _, _, _) = appVM.activeModalSheet {
            XCTAssertEqual(op.title, "Copy")
            XCTAssertEqual(items.map { $0.name }, ["doc.txt"])
        } else {
            XCTFail("Expected .copyMove(Copy) modal sheet")
        }
        appVM.activeModalSheet = nil

        appVM.actionMove()
        if case .copyMove(let op, let items, _, _, _) = appVM.activeModalSheet {
            XCTAssertEqual(op.title, "Move")
            XCTAssertEqual(items.map { $0.name }, ["doc.txt"])
        } else {
            XCTFail("Expected .copyMove(Move) modal sheet")
        }
        appVM.activeModalSheet = nil

        appVM.actionInfo()
        XCTAssertTrue(appVM.showInfoSheet)
        appVM.showInfoSheet = false
        XCTAssertNil(appVM.activeModalSheet)

        // 4. Settings button
        appVM.showSettingsSheet = true
        XCTAssertTrue(appVM.showSettingsSheet)
        appVM.showSettingsSheet = false
        XCTAssertNil(appVM.activeModalSheet)

        // 5. Test Duplicate & ArchiveBaseName context menu helpers
        XCTAssertEqual(appVM.ArchiveBaseName(for: [docItem], in: tempDirectoryURL.path), "doc")
        appVM.actionDuplicate(items: [docItem], in: appVM.leftPanel)
        let dupURL = tempDirectoryURL.appendingPathComponent("doc copy.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dupURL.path))
    }
}
