//
//  FilePanelView.swift
//  7-Zip GUI
//

import SwiftUI
import AppKit

/// A compact button that shows a double down-chevron and pops up an NSMenu on click without any system duplicate indicator.
struct PathHistoryDropdownButton: NSViewRepresentable {
    let quickLocations: [(title: String, path: String)]
    let recentFolders: [String]
    let onSelectPath: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = Self.makeDoubleChevronImage()
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.toolTip = "Recent Folders & Quick Locations"
        button.setAccessibilityIdentifier("PathDropdownButton")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.parent = self
    }

    private static func makeDoubleChevronImage() -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.secondaryLabelColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // Upper chevron
            path.move(to: NSPoint(x: 2.5, y: 8.5))
            path.line(to: NSPoint(x: 6.0, y: 5.5))
            path.line(to: NSPoint(x: 9.5, y: 8.5))

            // Lower chevron
            path.move(to: NSPoint(x: 2.5, y: 5.0))
            path.line(to: NSPoint(x: 6.0, y: 2.0))
            path.line(to: NSPoint(x: 9.5, y: 5.0))

            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    final class Coordinator: NSObject {
        var parent: PathHistoryDropdownButton

        init(_ parent: PathHistoryDropdownButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu(title: "Path History")

            let quickHeader = NSMenuItem.sectionHeader(withTitle: "Quick Locations")
            menu.addItem(quickHeader)

            for loc in parent.quickLocations {
                let item = NSMenuItem(title: loc.title, action: #selector(selectItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = loc.path
                menu.addItem(item)
            }

            if !parent.recentFolders.isEmpty {
                menu.addItem(.separator())
                let recentHeader = NSMenuItem.sectionHeader(withTitle: "Recent Folders")
                menu.addItem(recentHeader)

                for path in parent.recentFolders {
                    let item = NSMenuItem(title: path, action: #selector(selectItem(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = path
                    menu.addItem(item)
                }
            }

            let point = NSPoint(x: 0, y: sender.bounds.height + 2)
            menu.popUp(positioning: nil, at: point, in: sender)
        }

        @objc func selectItem(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            parent.onSelectPath(path)
        }
    }
}

private extension NSMenuItem {
    static func sectionHeader(withTitle title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

struct FilePanelView: View {
    @ObservedObject var viewModel: FilePanelViewModel
    let isActive: Bool
    let showActiveBorder: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 1. Panel Header Bar (Up Folder Button + Path Input + History Dropdown)
            panelHeaderBar

            // 2. Main File List (NSTableView wrapper)
            FileTableView(viewModel: viewModel, isActivePanel: isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 3. 7-Zip 4-part Status Bar
            panelStatusBar
        }
        .overlay(
            Rectangle()
                .stroke(
                    showActiveBorder && isActive ? Color.accentColor.opacity(0.8) : Color.clear,
                    lineWidth: 1.5
                )
                .allowsHitTesting(false)
        )
    }

    // MARK: - Header Bar

    private var panelHeaderBar: some View {
        HStack(spacing: 4) {
            // Parent Folder Button (like VIEW_PARENTFOLDER in 7-Zip)
            Button(action: {
                viewModel.onActivatePanel?()
                viewModel.navigateUp()
            }) {
                Image(systemName: "arrow.turn.left.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!viewModel.canGoUp)
            .help("Up One Level (Backspace)")
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            // Editable Path Bar + Dropdown Menu (like WC_COMBOBOXEXW in 7-Zip)
            HStack(spacing: 0) {
                Image(nsImage: folderHeaderIcon)
                    .resizable()
                    .frame(width: 15, height: 15)
                    .padding(.leading, 6)

                TextField("Path", text: $viewModel.pathInput, onCommit: {
                    viewModel.onActivatePanel?()
                    viewModel.navigateTo(path: viewModel.pathInput)
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)

                PathHistoryDropdownButton(
                    quickLocations: [
                        ("Root (/)", "/"),
                        ("Volumes (/Volumes)", "/Volumes"),
                        ("Home (\(FileManager.default.homeDirectoryForCurrentUser.lastPathComponent))", FileManager.default.homeDirectoryForCurrentUser.path)
                    ],
                    recentFolders: viewModel.pathHistory,
                    onSelectPath: { selectedPath in
                        viewModel.onActivatePanel?()
                        viewModel.navigateTo(path: selectedPath)
                    }
                )
                .frame(width: 24, height: 22)
                .padding(.trailing, 2)
            }
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1)
            )

            // Refresh button
            Button(action: {
                viewModel.onActivatePanel?()
                viewModel.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Refresh (Cmd+R)")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var folderHeaderIcon: NSImage {
        let iconPath = viewModel.currentArchivePath ?? viewModel.currentPath
        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    // MARK: - 4-Part Status Bar

    private var panelStatusBar: some View {
        HStack(spacing: 0) {
            // Part 0: "{selected} / {total} object(s) selected" (width ~220 in 7-Zip)
            Text(viewModel.statusObjectsText)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(width: 210, alignment: .leading)
                .padding(.horizontal, 6)

            Divider()
                .frame(height: 16)

            // Part 1: Total size of selected items (width ~100 in 7-Zip)
            Text(viewModel.statusSelectedSizeText)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .frame(width: 105, alignment: .trailing)
                .padding(.horizontal, 6)

            Divider()
                .frame(height: 16)

            // Part 2: Focused item size (width ~100 in 7-Zip)
            Text(viewModel.statusFocusedSizeText)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .frame(width: 105, alignment: .trailing)
                .padding(.horizontal, 6)

            Divider()
                .frame(height: 16)

            // Part 3: Focused item modification date (remaining width)
            Text(viewModel.statusFocusedDateText)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
        .frame(height: 22)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Divider(),
            alignment: .top
        )
    }
}
