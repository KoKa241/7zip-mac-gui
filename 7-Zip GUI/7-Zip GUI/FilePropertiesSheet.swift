//
//  FilePropertiesSheet.swift
//  7-Zip GUI
//

import SwiftUI

struct FilePropertiesSheet: View {
    let item: FileItem
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.fileType)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                propertyRow("Path:", item.archiveInternalPath ?? item.url.path)
                if !item.isDirectory {
                    propertyRow("Size:", "\(FileItem.format7ZipNumber(item.size)) bytes")
                    propertyRow("Packed / Disk Size:", "\(FileItem.format7ZipNumber(item.packedSize)) bytes")
                }
                propertyRow("Modified:", item.formattedModifiedDate)
                propertyRow("Created:", item.formattedCreatedDate)
                propertyRow("Accessed:", item.formattedAccessedDate)
                propertyRow("Attributes:", item.posixPermissions)
                if !item.method.isEmpty {
                    propertyRow("Method:", item.method)
                }
                if !item.crc.isEmpty {
                    propertyRow("CRC:", item.crc)
                }
                if item.archiveInternalPath != nil {
                    propertyRow("Encrypted:", item.isEncrypted ? "+" : "-")
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("OK") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 370)
    }

    private func propertyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 12))
                .textSelectionIfAvailable()
            Spacer()
        }
    }
}

private extension View {
    @ViewBuilder
    func textSelectionIfAvailable() -> some View {
        if #available(macOS 12.0, *) {
            self.textSelection(.enabled)
        } else {
            self
        }
    }
}
