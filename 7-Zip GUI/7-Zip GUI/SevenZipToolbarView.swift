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
    let modernSymbolName: String
    let tintColor: Color
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
                modernSymbolName: "plus.square.fill",
                tintColor: Color(red: 0.16, green: 0.68, blue: 0.38),
                tooltip: "Add files to archive",
                action: { appViewModel.actionAdd() }
            ),
            ToolbarButtonDescriptor(
                id: "extract",
                title: "Extract",
                largeAssetName: "Toolbar_Extract",
                smallAssetName: "Toolbar_Extract2",
                modernSymbolName: "arrow.up.bin.fill",
                tintColor: Color(red: 0.18, green: 0.52, blue: 0.96),
                tooltip: "Extract files from archive",
                action: { appViewModel.actionExtract() }
            ),
            ToolbarButtonDescriptor(
                id: "test",
                title: "Test",
                largeAssetName: "Toolbar_Test",
                smallAssetName: "Toolbar_Test2",
                modernSymbolName: "checkmark.shield.fill",
                tintColor: Color(red: 0.15, green: 0.65, blue: 0.60),
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
                modernSymbolName: "doc.on.doc.fill",
                tintColor: Color(red: 0.28, green: 0.50, blue: 0.88),
                tooltip: "Copy selected items (F5)",
                action: { appViewModel.actionCopy() }
            ),
            ToolbarButtonDescriptor(
                id: "move",
                title: "Move",
                largeAssetName: "Toolbar_Move",
                smallAssetName: "Toolbar_Move2",
                modernSymbolName: "folder.fill.badge.plus",
                tintColor: Color(red: 0.90, green: 0.55, blue: 0.15),
                tooltip: "Move selected items (F6)",
                action: { appViewModel.actionMove() }
            ),
            ToolbarButtonDescriptor(
                id: "delete",
                title: "Delete",
                largeAssetName: "Toolbar_Delete",
                smallAssetName: "Toolbar_Delete2",
                modernSymbolName: "trash.fill",
                tintColor: Color(red: 0.88, green: 0.24, blue: 0.24),
                tooltip: "Delete selected items (Del)",
                action: { appViewModel.actionDelete() }
            ),
            ToolbarButtonDescriptor(
                id: "info",
                title: "Info",
                largeAssetName: "Toolbar_Info",
                smallAssetName: "Toolbar_Info2",
                modernSymbolName: "info.circle.fill",
                tintColor: Color(red: 0.52, green: 0.40, blue: 0.88),
                tooltip: "File / Archive Properties (Cmd+I)",
                action: { appViewModel.actionInfo() }
            )
        ]
    }

    var body: some View {
        if appViewModel.showArchiveToolbar || appViewModel.showStandardToolbar {
            HStack(spacing: 4) {
                if appViewModel.showArchiveToolbar {
                    ForEach(archiveButtons) { btn in
                        SevenZipToolbarButton(
                            descriptor: btn,
                            iconStyle: appViewModel.toolbarIconStyle,
                            largeButtons: appViewModel.largeButtons,
                            showText: appViewModel.showButtonsText
                        )
                    }
                }

                if appViewModel.showArchiveToolbar && appViewModel.showStandardToolbar {
                    Divider()
                        .frame(height: appViewModel.largeButtons ? 40 : 24)
                        .padding(.horizontal, 4)
                }

                if appViewModel.showStandardToolbar {
                    ForEach(standardButtons) { btn in
                        SevenZipToolbarButton(
                            descriptor: btn,
                            iconStyle: appViewModel.toolbarIconStyle,
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
                    HStack(spacing: 5) {
                        Image(systemName: appViewModel.isDualPane ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                            .font(.system(size: 13, weight: .medium))
                        Text(appViewModel.isDualPane ? "2 Panels" : "1 Panel")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appViewModel.isDualPane ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(ToolbarInteractiveButtonStyle())
                .accessibilityIdentifier("ToolbarButton_PanelToggle")
                .help("Switch between 1 and 2 panels (F9)")

                // Settings / Preferences button
                Button(action: {
                    appViewModel.showSettingsSheet = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(ToolbarInteractiveButtonStyle())
                .accessibilityIdentifier("ToolbarButton_Settings")
                .help("Options & Theme Settings (Cmd+,)")
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

struct ToolbarInteractiveButtonStyle: ButtonStyle {
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.16)
                            : (isHovered ? Color.primary.opacity(0.08) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        configuration.isPressed || isHovered ? Color.primary.opacity(0.15) : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct SevenZipToolbarButton: View {
    let descriptor: ToolbarButtonDescriptor
    let iconStyle: ToolbarIconStyle
    let largeButtons: Bool
    let showText: Bool

    var body: some View {
        Button(action: descriptor.action) {
            VStack(spacing: 3) {
                iconView

                if showText {
                    Text(descriptor.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: largeButtons ? 56 : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarInteractiveButtonStyle())
        .accessibilityIdentifier("ToolbarButton_\(descriptor.id)")
        .accessibilityLabel(Text(descriptor.title))
        .help(descriptor.tooltip)
    }

    @ViewBuilder
    private var iconView: some View {
        if iconStyle == .modern {
            ZStack {
                RoundedRectangle(cornerRadius: largeButtons ? 8 : 5)
                    .fill(descriptor.tintColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: largeButtons ? 8 : 5)
                            .stroke(descriptor.tintColor.opacity(0.32), lineWidth: 0.8)
                    )

                Image(systemName: descriptor.modernSymbolName)
                    .font(.system(size: largeButtons ? 17 : 12, weight: .semibold))
                    .foregroundColor(descriptor.tintColor)
            }
            .frame(
                width: largeButtons ? 34 : 22,
                height: largeButtons ? 30 : 22
            )
        } else {
            let assetName = largeButtons ? descriptor.largeAssetName : descriptor.smallAssetName
            if let nsImage = NSImage(named: assetName) {
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: largeButtons ? 48 : 24,
                        height: largeButtons ? 36 : 24
                    )
            } else {
                Image(systemName: descriptor.modernSymbolName)
                    .font(.system(size: largeButtons ? 20 : 14))
                    .foregroundColor(descriptor.tintColor)
                    .frame(
                        width: largeButtons ? 34 : 22,
                        height: largeButtons ? 30 : 22
                    )
            }
        }
    }
}
