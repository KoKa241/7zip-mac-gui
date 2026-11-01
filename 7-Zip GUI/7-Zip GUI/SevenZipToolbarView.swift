//
//  SevenZipToolbarView.swift
//  7-Zip GUI
//

import SwiftUI

struct ToolbarButtonDescriptor: Identifiable {
    let id: String
    let title: String
    let largeAssetName: String
    let smallAssetName: String
    let fallbackSystemSymbol: String
    let tooltip: String
    let action: () -> Void
}

struct SevenZipToolbarView: View {
    @ObservedObject var appViewModel: FileManagerAppViewModel

    private var archiveButtons: [ToolbarButtonDescriptor] {
        [
            ToolbarButtonDescriptor(
                id: "add",
                title: "Add",
                largeAssetName: "Toolbar_Add",
                smallAssetName: "Toolbar_Add2",
                fallbackSystemSymbol: "plus.rectangle.on.folder",
                tooltip: "Add files to archive",
                action: { appViewModel.actionAdd() }
            ),
            ToolbarButtonDescriptor(
                id: "extract",
                title: "Extract",
                largeAssetName: "Toolbar_Extract",
                smallAssetName: "Toolbar_Extract2",
                fallbackSystemSymbol: "arrow.up.bin",
                tooltip: "Extract files from archive",
                action: { appViewModel.actionExtract() }
            ),
            ToolbarButtonDescriptor(
                id: "test",
                title: "Test",
                largeAssetName: "Toolbar_Test",
                smallAssetName: "Toolbar_Test2",
                fallbackSystemSymbol: "checkmark.shield",
                tooltip: "Test archive integrity",
                action: { appViewModel.actionTest() }
            )
        ]
    }

    private var standardButtons: [ToolbarButtonDescriptor] {
        [
            ToolbarButtonDescriptor(
                id: "copy",
                title: "Copy",
                largeAssetName: "Toolbar_Copy",
                smallAssetName: "Toolbar_Copy2",
                fallbackSystemSymbol: "doc.on.doc",
                tooltip: "Copy selected items (F5)",
                action: { appViewModel.actionCopy() }
            ),
            ToolbarButtonDescriptor(
                id: "move",
                title: "Move",
                largeAssetName: "Toolbar_Move",
                smallAssetName: "Toolbar_Move2",
                fallbackSystemSymbol: "folder.badge.gearshape",
                tooltip: "Move selected items (F6)",
                action: { appViewModel.actionMove() }
            ),
            ToolbarButtonDescriptor(
                id: "delete",
                title: "Delete",
                largeAssetName: "Toolbar_Delete",
                smallAssetName: "Toolbar_Delete2",
                fallbackSystemSymbol: "xmark.bin",
                tooltip: "Delete selected items (Del)",
                action: { appViewModel.actionDelete() }
            ),
            ToolbarButtonDescriptor(
                id: "info",
                title: "Info",
                largeAssetName: "Toolbar_Info",
                smallAssetName: "Toolbar_Info2",
                fallbackSystemSymbol: "info.circle",
                tooltip: "File / Archive Properties (Alt+Enter)",
                action: { appViewModel.actionInfo() }
            )
        ]
    }

    var body: some View {
        if appViewModel.showArchiveToolbar || appViewModel.showStandardToolbar {
            HStack(spacing: 2) {
                if appViewModel.showArchiveToolbar {
                    ForEach(archiveButtons) { btn in
                        SevenZipToolbarButton(
                            descriptor: btn,
                            largeButtons: appViewModel.largeButtons,
                            showText: appViewModel.showButtonsText
                        )
                    }
                }

                if appViewModel.showArchiveToolbar && appViewModel.showStandardToolbar {
                    Divider()
                        .frame(height: appViewModel.largeButtons ? 44 : 24)
                        .padding(.horizontal, 4)
                }

                if appViewModel.showStandardToolbar {
                    ForEach(standardButtons) { btn in
                        SevenZipToolbarButton(
                            descriptor: btn,
                            largeButtons: appViewModel.largeButtons,
                            showText: appViewModel.showButtonsText
                        )
                    }
                }

                Spacer()

                // Quick toggle for 1 / 2 panels (F9 in 7-Zip)
                Button(action: {
                    appViewModel.toggleDualPane()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: appViewModel.isDualPane ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                        Text(appViewModel.isDualPane ? "2 Panels" : "1 Panel")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(appViewModel.isDualPane ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help("Switch between 1 and 2 panels (F9)")
                .padding(.trailing, 6)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

struct SevenZipToolbarButton: View {
    let descriptor: ToolbarButtonDescriptor
    let largeButtons: Bool
    let showText: Bool

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: descriptor.action) {
            VStack(spacing: 2) {
                iconView
                    .frame(
                        width: largeButtons ? 48 : 24,
                        height: largeButtons ? 36 : 24
                    )

                if showText {
                    Text(descriptor.title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: largeButtons ? 58 : 36)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHovered ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(descriptor.tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let assetName = largeButtons ? descriptor.largeAssetName : descriptor.smallAssetName
        if let nsImage = NSImage(named: assetName) {
            Image(nsImage: nsImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: descriptor.fallbackSystemSymbol)
                .font(.system(size: largeButtons ? 22 : 15))
        }
    }
}
