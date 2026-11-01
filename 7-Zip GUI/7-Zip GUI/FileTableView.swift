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

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
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
        label.TextColor = .labelColor

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

private extension NSTextField {
    var TextColor: NSColor? {
        get { textColor }
        set { textColor = newValue }
    }
}
