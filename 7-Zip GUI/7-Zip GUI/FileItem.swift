//
//  FileItem.swift
//  7-Zip GUI
//

import Foundation
import AppKit

enum FileSortColumn: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case modified = "Modified"
    case created = "Created"
    case accessed = "Accessed"
    case attributes = "Attributes"
    case packedSize = "Packed Size"
    case comment = "Comment"
    case type = "Type"
}

struct FileItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let isParentEntry: Bool // ".."
    let size: UInt64
    let packedSize: UInt64
    let modifiedDate: Date?
    let createdDate: Date?
    let accessedDate: Date?
    let posixPermissions: String
    let fileType: String
    let comment: String
    let icon: NSImage

    static func parentEntry(for parentURL: URL) -> FileItem {
        let folderIcon = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        folderIcon.size = NSSize(width: 16, height: 16)
        return FileItem(
            id: "..",
            url: parentURL,
            name: "..",
            isDirectory: true,
            isParentEntry: true,
            size: 0,
            packedSize: 0,
            modifiedDate: nil,
            createdDate: nil,
            accessedDate: nil,
            posixPermissions: "",
            fileType: "Folder",
            comment: "",
            icon: folderIcon
        )
    }

    var formattedSize: String {
        if isParentEntry || isDirectory {
            return ""
        }
        return Self.format7ZipNumber(size)
    }

    var formattedPackedSize: String {
        if isParentEntry || isDirectory {
            return ""
        }
        return Self.format7ZipNumber(packedSize)
    }

    var formattedModifiedDate: String {
        Self.formatDate(modifiedDate)
    }

    var formattedCreatedDate: String {
        Self.formatDate(createdDate)
    }

    var formattedAccessedDate: String {
        Self.formatDate(accessedDate)
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func format7ZipNumber(_ value: UInt64) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return dateFormatter.string(from: date)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.name == rhs.name &&
        lhs.isDirectory == rhs.isDirectory &&
        lhs.isParentEntry == rhs.isParentEntry &&
        lhs.size == rhs.size &&
        lhs.packedSize == rhs.packedSize &&
        lhs.modifiedDate == rhs.modifiedDate &&
        lhs.createdDate == rhs.createdDate &&
        lhs.accessedDate == rhs.accessedDate &&
        lhs.posixPermissions == rhs.posixPermissions &&
        lhs.fileType == rhs.fileType &&
        lhs.comment == rhs.comment
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(url)
        hasher.combine(name)
        hasher.combine(isDirectory)
        hasher.combine(size)
        hasher.combine(modifiedDate)
    }
}
