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
        let baseTemp = FileManager.default.temporaryDirectory
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
}
