//
//  FileTableView.swift
//  7-Zip GUI
//

import SwiftUI
import AppKit

struct FileTableView: NSViewRepresentable {
    @ObservedObject var viewModel: FilePanelViewModel
    let isActivePanel: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let tableView = SevenZipNSTableView()
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 6, height: 2)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing

        setupColumns(for: tableView)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        tableView.onEnterOrDoubleClick = { [weak coordinator = context.coordinator] in
            coordinator?.activateSelectedOrFocusedItem()
        }
        tableView.onBackspace = { [weak coordinator = context.coordinator] in
            coordinator?.parent.viewModel.navigateUp()
        }
        tableView.onFocusPanel = { [weak coordinator = context.coordinator] in
            coordinator?.parent.viewModel.onActivatePanel?()
        }
        tableView.menu = context.coordinator.makeContextMenu()

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView else { return }

        if context.coordinator.lastItems != viewModel.items ||
           context.coordinator.lastSortColumn != viewModel.sortColumn ||
           context.coordinator.lastSortAscending != viewModel.sortAscending {
            context.coordinator.lastItems = viewModel.items
            context.coordinator.lastSortColumn = viewModel.sortColumn
            context.coordinator.lastSortAscending = viewModel.sortAscending

            context.coordinator.isProgrammaticUpdate = true
            tableView.reloadData()
            updateSortIndicator(in: tableView)
            syncSelectionToTable(tableView, coordinator: context.coordinator)
            context.coordinator.isProgrammaticUpdate = false
        } else if context.coordinator.lastSelectedIDs != viewModel.selectedIDs {
            context.coordinator.isProgrammaticUpdate = true
            syncSelectionToTable(tableView, coordinator: context.coordinator)
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    private func syncSelectionToTable(_ tableView: NSTableView, coordinator: Coordinator) {
        var indexSet = IndexSet()
        for (idx, item) in viewModel.items.enumerated() {
            if viewModel.selectedIDs.contains(item.id) {
                indexSet.insert(idx)
            }
        }
        coordinator.lastSelectedIDs = viewModel.selectedIDs
        if tableView.selectedRowIndexes != indexSet {
            tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
        }
    }

    private func setupColumns(for tableView: NSTableView) {
        let columns: [(FileSortColumn, CGFloat, CGFloat, NSTextAlignment)] = [
            (.name, 250, 120, .left),
            (.size, 100, 60, .right),
            (.modified, 130, 90, .left),
            (.created, 130, 90, .left),
            (.accessed, 130, 90, .left),
            (.attributes, 95, 70, .left),
            (.packedSize, 100, 60, .right),
            (.comment, 120, 60, .left)
        ]

        for (col, width, minWidth, alignment) in columns {
            let identifier = NSUserInterfaceItemIdentifier(col.rawValue)
            let tableColumn = NSTableColumn(identifier: identifier)
            tableColumn.title = col.rawValue
            tableColumn.width = width
            tableColumn.minWidth = minWidth
            tableColumn.maxWidth = 1200
            tableColumn.headerCell.alignment = alignment
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: col.rawValue, ascending: true)
            tableView.addTableColumn(tableColumn)
        }

        updateSortIndicator(in: tableView)
    }

    private func updateSortIndicator(in tableView: NSTableView) {
        for column in tableView.tableColumns {
            tableView.setIndicatorImage(nil, in: column)
        }
        let activeID = NSUserInterfaceItemIdentifier(viewModel.sortColumn.rawValue)
        if let col = tableView.tableColumn(withIdentifier: activeID) {
            let imageName = viewModel.sortAscending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"
            if let indicator = NSImage(named: imageName) {
                tableView.setIndicatorImage(indicator, in: col)
            }
            tableView.highlightedTableColumn = col
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?
        var lastItems: [FileItem] = []
        var lastSelectedIDs: Set<String> = []
        var lastSortColumn: FileSortColumn = .name
        var lastSortAscending: Bool = true
        var isProgrammaticUpdate: Bool = false

        init(_ parent: FileTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return parent.viewModel.items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < parent.viewModel.items.count,
                  let tableColumn = tableColumn else {
                return nil
            }

            let item = parent.viewModel.items[row]
            let colID = tableColumn.identifier.rawValue
            guard let colType = FileSortColumn(rawValue: colID) else { return nil }

            if colType == .name {
                let cellID = NSUserInterfaceItemIdentifier("NameCell")
                let cellView: NameTableCellView
                if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NameTableCellView {
                    cellView = reused
                } else {
                    cellView = NameTableCellView()
                    cellView.identifier = cellID
                }
                cellView.configure(name: item.name, icon: item.icon)
                return cellView
            } else {
                let cellID = NSUserInterfaceItemIdentifier("TextCell_\(colID)")
                let cellView: TextTableCellView
                let isRightAligned = (colType == .size || colType == .packedSize)
                if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? TextTableCellView {
                    cellView = reused
                } else {
                    cellView = TextTableCellView(alignment: isRightAligned ? .right : .left, monospaced: isRightAligned || colType == .attributes)
                    cellView.identifier = cellID
                }

                let text: String
                switch colType {
                case .size: text = item.formattedSize
                case .modified: text = item.formattedModifiedDate
                case .created: text = item.formattedCreatedDate
                case .accessed: text = item.formattedAccessedDate
                case .attributes: text = item.posixPermissions
                case .packedSize: text = item.formattedPackedSize
                case .comment: text = item.comment
                case .type: text = item.fileType
                case .name: text = item.name
                }

                cellView.configure(text: text)
                return cellView
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let tableView = tableView else { return }
            parent.viewModel.onActivatePanel?()

            let selectedIndexes = tableView.selectedRowIndexes
            var ids = Set<String>()
            var focused: FileItem? = nil

            for index in selectedIndexes {
                if index >= 0 && index < parent.viewModel.items.count {
                    let item = parent.viewModel.items[index]
                    if !item.isParentEntry {
                        ids.insert(item.id)
                    }
                    if focused == nil {
                        focused = item
                    }
                }
            }

            if tableView.clickedRow >= 0 && tableView.clickedRow < parent.viewModel.items.count {
                focused = parent.viewModel.items[tableView.clickedRow]
            } else if let lastIdx = selectedIndexes.last, lastIdx < parent.viewModel.items.count {
                focused = parent.viewModel.items[lastIdx]
            }

            lastSelectedIDs = ids
            parent.viewModel.updateSelection(ids: ids, focused: focused)
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let first = tableView.sortDescriptors.first,
                  let key = first.key,
                  let column = FileSortColumn(rawValue: key) else { return }
            parent.viewModel.onActivatePanel?()
            parent.viewModel.setSort(column: column, ascending: first.ascending)
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView = tableView else { return }
            parent.viewModel.onActivatePanel?()
            let row = tableView.clickedRow
            guard row >= 0 && row < parent.viewModel.items.count else { return }
            let item = parent.viewModel.items[row]
            parent.viewModel.openItem(item)
        }

        func activateSelectedOrFocusedItem() {
            guard let tableView = tableView else { return }
            let row = tableView.selectedRow
            guard row >= 0 && row < parent.viewModel.items.count else { return }
            let item = parent.viewModel.items[row]
            parent.viewModel.openItem(item)
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu(title: "Context")
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            parent.viewModel.onActivatePanel?()

            let vm = parent.viewModel
            if let tableView = tableView {
                let clickedRow = tableView.clickedRow
                if clickedRow >= 0 && clickedRow < vm.items.count {
                    let clickedItem = vm.items[clickedRow]
                    if !clickedItem.isParentEntry {
                        if !vm.selectedIDs.contains(clickedItem.id) {
                            isProgrammaticUpdate = true
                            tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                            isProgrammaticUpdate = false
                            lastSelectedIDs = [clickedItem.id]
                            vm.updateSelection(ids: [clickedItem.id], focused: clickedItem)
                        } else {
                            vm.updateSelection(ids: vm.selectedIDs, focused: clickedItem)
                        }
                    }
                }
            }

            let targetItems = targetItemsForContextMenu()
            let singleItem = targetItems.count == 1 ? targetItems.first : nil
            let clickedParentEntry: Bool = {
                guard let tableView = tableView, tableView.clickedRow >= 0, tableView.clickedRow < vm.items.count else {
                    return false
                }
                return vm.items[tableView.clickedRow].isParentEntry
            }()

            if clickedParentEntry {
                menu.addItem(makeMenuItem("Up One Level", action: #selector(contextOpenParent(_:)), symbol: "arrow.turn.left.up"))
                menu.addItem(.separator())
                menu.addItem(makeMenuItem("Refresh", action: #selector(contextRefresh(_:)), symbol: "arrow.clockwise"))
                return
            }

            // 1. Open / Reveal section
            if let item = singleItem {
                if !vm.isInsideArchive && !item.isDirectory && SevenZipEngine.isArchiveFile(url: item.url) {
                    menu.addItem(makeMenuItem("Open Inside 7-Zip", action: #selector(contextOpen(_:)), symbol: "doc.zipper"))
                    menu.addItem(makeMenuItem("Open With Default App", action: #selector(contextOpenExternal(_:)), symbol: "arrow.up.forward.app"))
                } else {
                    menu.addItem(makeMenuItem("Open", action: #selector(contextOpen(_:)), symbol: item.isDirectory ? "folder" : "doc.text"))
                }
            }

            if !vm.isInsideArchive {
                let revealTitle = targetItems.isEmpty ? "Show Folder in Finder" : "Show in Finder"
                menu.addItem(makeMenuItem(revealTitle, action: #selector(contextShowInFinder(_:)), symbol: "finder"))
            }

            menu.addItem(.separator())

            // 2. 7-Zip Archive Operations section
            if !vm.isInsideArchive && !targetItems.isEmpty {
                let baseName = vm.appViewModel?.ArchiveBaseName(for: targetItems, in: vm.currentPath) ?? "archive"
                menu.addItem(makeMenuItem("Add to Archive...", action: #selector(contextAddToArchive(_:)), symbol: "plus.rectangle.on.folder"))
                menu.addItem(makeMenuItem("Add to \"\(baseName).7z\"", action: #selector(contextQuickAdd7z(_:)), symbol: "bolt.fill"))
                menu.addItem(makeMenuItem("Add to \"\(baseName).zip\"", action: #selector(contextQuickAddZip(_:)), symbol: "bolt"))
            }

            let isTargetArchiveFile = !vm.isInsideArchive && singleItem != nil && !singleItem!.isDirectory && SevenZipEngine.isArchiveFile(url: singleItem!.url)
            if isTargetArchiveFile || vm.isInsideArchive {
                if !vm.isInsideArchive {
                    menu.addItem(.separator())
                }
                menu.addItem(makeMenuItem("Extract Files...", action: #selector(contextExtractDialog(_:)), symbol: "arrow.up.bin"))

                if let archiveItem = singleItem, isTargetArchiveFile {
                    let folderBase = (archiveItem.name as NSString).deletingPathExtension
                    menu.addItem(makeMenuItem("Extract Here", action: #selector(contextExtractHere(_:)), symbol: "tray.and.arrow.down"))
                    menu.addItem(makeMenuItem("Extract to \"\(folderBase)/\"", action: #selector(contextExtractToSubfolder(_:)), symbol: "folder.badge.plus"))
                }

                menu.addItem(makeMenuItem("Test Archive", action: #selector(contextTestArchive(_:)), symbol: "checkmark.shield"))
            }

            menu.addItem(.separator())

            // 3. File Management section (Copy, Move, Duplicate, Rename, New Folder, Delete)
            if !targetItems.isEmpty {
                menu.addItem(makeMenuItem("Copy To... (F5)", action: #selector(contextCopyTo(_:)), symbol: "doc.on.doc"))
                menu.addItem(makeMenuItem("Move To... (F6)", action: #selector(contextMoveTo(_:)), symbol: "folder.badge.gearshape"))

                if !vm.isInsideArchive {
                    menu.addItem(makeMenuItem("Duplicate", action: #selector(contextDuplicate(_:)), symbol: "plus.square.on.square"))
                    if singleItem != nil {
                        menu.addItem(makeMenuItem("Rename...", action: #selector(contextRename(_:)), symbol: "pencil"))
                    }
                }
            }

            if !vm.isInsideArchive {
                menu.addItem(makeMenuItem("New Folder... (F7)", action: #selector(contextNewFolder(_:)), symbol: "folder.badge.plus"))
            }

            if !targetItems.isEmpty {
                let deleteTitle = vm.isInsideArchive ? "Delete from Archive" : "Move to Trash"
                menu.addItem(makeMenuItem(deleteTitle, action: #selector(contextDelete(_:)), symbol: "trash"))
            }

            menu.addItem(.separator())

            // 4. Clipboard & Selection section
            if !targetItems.isEmpty {
                if !vm.isInsideArchive {
                    menu.addItem(makeMenuItem("Copy File to Clipboard", action: #selector(contextCopyFilesToClipboard(_:)), symbol: "doc.on.clipboard"))
                }
                menu.addItem(makeMenuItem("Copy Path", action: #selector(contextCopyPath(_:)), symbol: "link"))
                menu.addItem(makeMenuItem("Copy Name", action: #selector(contextCopyName(_:)), symbol: "textformat"))
                menu.addItem(.separator())
            }

            menu.addItem(makeMenuItem("Select All", action: #selector(contextSelectAll(_:)), symbol: "checkmark.circle"))
            menu.addItem(makeMenuItem("Invert Selection", action: #selector(contextInvertSelection(_:)), symbol: "arrow.triangle.2.circlepath"))
            menu.addItem(makeMenuItem("Refresh", action: #selector(contextRefresh(_:)), symbol: "arrow.clockwise"))

            menu.addItem(.separator())

            // 5. Properties / Info
            menu.addItem(makeMenuItem("Properties / Info", action: #selector(contextProperties(_:)), symbol: "info.circle"))
        }

        private func makeMenuItem(_ title: String, action: Selector, symbol: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
                img.isTemplate = true
                item.image = img
            }
            return item
        }

        private func targetItemsForContextMenu() -> [FileItem] {
            let vm = parent.viewModel
            let selected = vm.effectiveSelectedItems
            if !selected.isEmpty {
                return selected
            }
            if let item = targetItemForContextMenu(), !item.isParentEntry {
                return [item]
            }
            return []
        }

        private func targetItemForContextMenu() -> FileItem? {
            guard let tableView = tableView else { return nil }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0 && row < parent.viewModel.items.count else { return nil }
            return parent.viewModel.items[row]
        }

        @objc func contextOpenParent(_ sender: Any?) {
            parent.viewModel.navigateUp()
        }

        @objc func contextOpen(_ sender: Any?) {
            guard let item = targetItemForContextMenu() else { return }
            parent.viewModel.openItem(item)
        }

        @objc func contextOpenExternal(_ sender: Any?) {
            guard let item = targetItemForContextMenu(), !item.isParentEntry else { return }
            NSWorkspace.shared.open(item.url)
        }

        @objc func contextShowInFinder(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            if !items.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(items.map { $0.url })
            } else {
                let folderURL = URL(fileURLWithPath: parent.viewModel.currentPath)
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            }
        }

        @objc func contextAddToArchive(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionAdd()
        }

        @objc func contextQuickAdd7z(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            parent.viewModel.appViewModel?.quickCompress(items: items, in: parent.viewModel.currentPath, format: .sevenZ)
        }

        @objc func contextQuickAddZip(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            parent.viewModel.appViewModel?.quickCompress(items: items, in: parent.viewModel.currentPath, format: .zip)
        }

        @objc func contextExtractDialog(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionExtract()
        }

        @objc func contextExtractHere(_ sender: Any?) {
            guard let item = targetItemsForContextMenu().first else { return }
            parent.viewModel.appViewModel?.extractHere(archivePath: item.url.path, destinationDirectory: parent.viewModel.currentPath)
        }

        @objc func contextExtractToSubfolder(_ sender: Any?) {
            guard let item = targetItemsForContextMenu().first else { return }
            parent.viewModel.appViewModel?.extractToSubfolder(archivePath: item.url.path, parentDirectory: parent.viewModel.currentPath)
        }

        @objc func contextTestArchive(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionTest()
        }

        @objc func contextCopyTo(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionCopy()
        }

        @objc func contextMoveTo(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionMove()
        }

        @objc func contextDuplicate(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            parent.viewModel.appViewModel?.actionDuplicate(items: items, in: parent.viewModel.currentPath.isEmpty ? parent.viewModel : parent.viewModel)
        }

        @objc func contextRename(_ sender: Any?) {
            guard let item = targetItemsForContextMenu().first else { return }
            parent.viewModel.appViewModel?.actionRename(item: item, in: parent.viewModel)
        }

        @objc func contextNewFolder(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionCreateFolder()
        }

        @objc func contextDelete(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionDelete()
        }

        @objc func contextCopyFilesToClipboard(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            parent.viewModel.appViewModel?.copyFilesToPasteboard(items: items)
        }

        @objc func contextCopyPath(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            let paths = items.map { $0.archiveInternalPath ?? $0.url.path }.joined(separator: "\n")
            guard !paths.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
        }

        @objc func contextCopyName(_ sender: Any?) {
            let items = targetItemsForContextMenu()
            let names = items.map { $0.name }.joined(separator: "\n")
            guard !names.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(names, forType: .string)
        }

        @objc func contextSelectAll(_ sender: Any?) {
            parent.viewModel.selectAll()
        }

        @objc func contextInvertSelection(_ sender: Any?) {
            parent.viewModel.invertSelection()
        }

        @objc func contextRefresh(_ sender: Any?) {
            parent.viewModel.refresh()
        }

        @objc func contextProperties(_ sender: Any?) {
            parent.viewModel.appViewModel?.actionInfo()
        }
    }
}

// MARK: - Custom NSTableView Subclass for Keyboard Navigation

final class SevenZipNSTableView: NSTableView {
    var onEnterOrDoubleClick: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onFocusPanel: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocusPanel?()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        onFocusPanel?()
        switch event.keyCode {
        case 36, 76: // Return or Keypad Enter
            onEnterOrDoubleClick?()
        case 51: // Backspace / Delete
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                onBackspace?()
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Lightweight Cell Views

final class NameTableCellView: NSTableCellView {
    private let iconImageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .labelColor

        addSubview(iconImageView)
        addSubview(label)
        self.textField = label
        self.imageView = iconImageView

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(name: String, icon: NSImage) {
        label.stringValue = name
        iconImageView.image = icon
    }
}

final class TextTableCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(alignment: NSTextAlignment, monospaced: Bool) {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        if monospaced {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        } else {
            label.font = NSFont.systemFont(ofSize: 12)
        }
        addSubview(label)
        self.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        label.stringValue = text
    }
}
