//
//  FilePanelView.swift
//  7-Zip GUI
//

import SwiftUI

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
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.onActivatePanel?()
        }
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

                Menu {
                    Section(header: Text("Quick Locations")) {
                        Button("Root (/)") {
                            viewModel.onActivatePanel?()
                            viewModel.navigateTo(path: "/")
                        }
                        Button("Volumes (/Volumes)") {
                            viewModel.onActivatePanel?()
                            viewModel.navigateTo(path: "/Volumes")
                        }
                        Button("Home (\(FileManager.default.homeDirectoryForCurrentUser.lastPathComponent))") {
                            viewModel.onActivatePanel?()
                            viewModel.navigateTo(path: FileManager.default.homeDirectoryForCurrentUser.path)
                        }
                    }

                    if !viewModel.pathHistory.isEmpty {
                        Divider()
                        Section(header: Text("Recent Folders")) {
                            ForEach(viewModel.pathHistory, id: \.self) { path in
                                Button(action: {
                                    viewModel.onActivatePanel?()
                                    viewModel.navigateTo(path: path)
                                }) {
                                    Text(path)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .frame(width: 22)
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
        let icon = NSWorkspace.shared.icon(forFile: viewModel.currentPath)
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
