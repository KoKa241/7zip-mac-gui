//
//  KeyboardShortcuts.swift
//  7-Zip GUI
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Strongly-Typed Shortcut Names

extension KeyboardShortcuts.Name {
    // Archive Operations
    /// Hotkey to trigger the Add to Archive dialog (`actionAdd()`). Default: ⇧ + ⌘ + A
    static let addArchive = Self(
        "addArchive",
        default: .init(.a, modifiers: [.command, .shift])
    )

    /// Hotkey to trigger the Extract Archive dialog (`actionExtract()`). Default: ⇧ + ⌘ + E
    static let extractArchive = Self(
        "extractArchive",
        default: .init(.e, modifiers: [.command, .shift])
    )

    /// Hotkey to trigger Test Archive integrity check (`actionTest()`). Default: ⇧ + ⌘ + T
    static let testArchive = Self(
        "testArchive",
        default: .init(.t, modifiers: [.command, .shift])
    )

    // File Management Operations
    /// Hotkey to copy selected items (`actionCopy()`). Default: F5
    static let copyItems = Self(
        "copyItems",
        default: .init(.f5, modifiers: [])
    )

    /// Hotkey to move selected items (`actionMove()`). Default: F6
    static let moveItems = Self(
        "moveItems",
        default: .init(.f6, modifiers: [])
    )

    /// Hotkey to create a new folder (`actionCreateFolder()`). Default: F7
    static let createFolder = Self(
        "createFolder",
        default: .init(.f7, modifiers: [])
    )

    /// Hotkey to delete selected items (`actionDelete()`). Default: ⌘ + ⌫
    static let deleteItems = Self(
        "deleteItems",
        default: .init(.delete, modifiers: [.command])
    )

    /// Hotkey to open Properties / Info (`actionInfo()`). Default: ⌘ + I
    static let showInfo = Self(
        "showInfo",
        default: .init(.i, modifiers: [.command])
    )

    // View & Navigation Operations
    /// Hotkey to toggle between 1-Panel and 2-Panel mode (`toggleDualPane()`). Default: F9
    static let toggleDualPane = Self(
        "toggleDualPane",
        default: .init(.f9, modifiers: [])
    )

    /// Hotkey to navigate up one directory level (`navigateUp()`). Default: ⌘ + ↑
    static let navigateUp = Self(
        "navigateUp",
        default: .init(.upArrow, modifiers: [.command])
    )

    /// Hotkey to refresh the active panel (`refresh()`). Default: ⌘ + R
    static let refreshPanel = Self(
        "refreshPanel",
        default: .init(.r, modifiers: [.command])
    )

    /// Hotkey to toggle showing hidden files. Default: ⇧ + ⌘ + .
    static let toggleHiddenFiles = Self(
        "toggleHiddenFiles",
        default: .init(.period, modifiers: [.command, .shift])
    )

    static let allCustomizable: [Self] = [
        .addArchive,
        .extractArchive,
        .testArchive,
        .copyItems,
        .moveItems,
        .createFolder,
        .deleteItems,
        .showInfo,
        .toggleDualPane,
        .navigateUp,
        .refreshPanel,
        .toggleHiddenFiles
    ]
}

// MARK: - KeyboardShortcuts Namespace

enum KeyboardShortcuts {

    // MARK: - 1. Name (Strongly Typed Identifier)

    struct Name: Hashable, Equatable {
        let rawValue: String
        let defaultShortcut: Shortcut?

        init(_ rawValue: String, default defaultShortcut: Shortcut? = nil) {
            self.rawValue = rawValue
            self.defaultShortcut = defaultShortcut
            if let def = defaultShortcut {
                KeyboardShortcuts.registerDefault(def, for: self)
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue == rhs.rawValue
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue)
        }
    }

    // MARK: - 2. Key Representation

    struct Key: Hashable, Codable, Equatable {
        let rawValue: UInt16

        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        static let a = Self(rawValue: UInt16(kVK_ANSI_A))
        static let b = Self(rawValue: UInt16(kVK_ANSI_B))
        static let c = Self(rawValue: UInt16(kVK_ANSI_C))
        static let d = Self(rawValue: UInt16(kVK_ANSI_D))
        static let e = Self(rawValue: UInt16(kVK_ANSI_E))
        static let f = Self(rawValue: UInt16(kVK_ANSI_F))
        static let g = Self(rawValue: UInt16(kVK_ANSI_G))
        static let h = Self(rawValue: UInt16(kVK_ANSI_H))
        static let i = Self(rawValue: UInt16(kVK_ANSI_I))
        static let j = Self(rawValue: UInt16(kVK_ANSI_J))
        static let k = Self(rawValue: UInt16(kVK_ANSI_K))
        static let l = Self(rawValue: UInt16(kVK_ANSI_L))
        static let m = Self(rawValue: UInt16(kVK_ANSI_M))
        static let n = Self(rawValue: UInt16(kVK_ANSI_N))
        static let o = Self(rawValue: UInt16(kVK_ANSI_O))
        static let p = Self(rawValue: UInt16(kVK_ANSI_P))
        static let q = Self(rawValue: UInt16(kVK_ANSI_Q))
        static let r = Self(rawValue: UInt16(kVK_ANSI_R))
        static let s = Self(rawValue: UInt16(kVK_ANSI_S))
        static let t = Self(rawValue: UInt16(kVK_ANSI_T))
        static let u = Self(rawValue: UInt16(kVK_ANSI_U))
        static let v = Self(rawValue: UInt16(kVK_ANSI_V))
        static let w = Self(rawValue: UInt16(kVK_ANSI_W))
        static let x = Self(rawValue: UInt16(kVK_ANSI_X))
        static let y = Self(rawValue: UInt16(kVK_ANSI_Y))
        static let z = Self(rawValue: UInt16(kVK_ANSI_Z))

        static let zero = Self(rawValue: UInt16(kVK_ANSI_0))
        static let one = Self(rawValue: UInt16(kVK_ANSI_1))
        static let two = Self(rawValue: UInt16(kVK_ANSI_2))
        static let three = Self(rawValue: UInt16(kVK_ANSI_3))
        static let four = Self(rawValue: UInt16(kVK_ANSI_4))
        static let five = Self(rawValue: UInt16(kVK_ANSI_5))
        static let six = Self(rawValue: UInt16(kVK_ANSI_6))
        static let seven = Self(rawValue: UInt16(kVK_ANSI_7))
        static let eight = Self(rawValue: UInt16(kVK_ANSI_8))
        static let nine = Self(rawValue: UInt16(kVK_ANSI_9))

        static let f1 = Self(rawValue: UInt16(kVK_F1))
        static let f2 = Self(rawValue: UInt16(kVK_F2))
        static let f3 = Self(rawValue: UInt16(kVK_F3))
        static let f4 = Self(rawValue: UInt16(kVK_F4))
        static let f5 = Self(rawValue: UInt16(kVK_F5))
        static let f6 = Self(rawValue: UInt16(kVK_F6))
        static let f7 = Self(rawValue: UInt16(kVK_F7))
        static let f8 = Self(rawValue: UInt16(kVK_F8))
        static let f9 = Self(rawValue: UInt16(kVK_F9))
        static let f10 = Self(rawValue: UInt16(kVK_F10))
        static let f11 = Self(rawValue: UInt16(kVK_F11))
        static let f12 = Self(rawValue: UInt16(kVK_F12))

        static let delete = Self(rawValue: UInt16(kVK_Delete))
        static let forwardDelete = Self(rawValue: UInt16(kVK_ForwardDelete))
        static let upArrow = Self(rawValue: UInt16(kVK_UpArrow))
        static let downArrow = Self(rawValue: UInt16(kVK_DownArrow))
        static let leftArrow = Self(rawValue: UInt16(kVK_LeftArrow))
        static let rightArrow = Self(rawValue: UInt16(kVK_RightArrow))
        static let period = Self(rawValue: UInt16(kVK_ANSI_Period))
        static let comma = Self(rawValue: UInt16(kVK_ANSI_Comma))
        static let slash = Self(rawValue: UInt16(kVK_ANSI_Slash))
        static let backslash = Self(rawValue: UInt16(kVK_ANSI_Backslash))

        var displayString: String {
            switch Int(rawValue) {
            case kVK_ANSI_A: return "A"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_C: return "C"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_E: return "E"
            case kVK_ANSI_F: return "F"
            case kVK_ANSI_G: return "G"
            case kVK_ANSI_H: return "H"
            case kVK_ANSI_I: return "I"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_L: return "L"
            case kVK_ANSI_M: return "M"
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_O: return "O"
            case kVK_ANSI_P: return "P"
            case kVK_ANSI_Q: return "Q"
            case kVK_ANSI_R: return "R"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_T: return "T"
            case kVK_ANSI_U: return "U"
            case kVK_ANSI_V: return "V"
            case kVK_ANSI_W: return "W"
            case kVK_ANSI_X: return "X"
            case kVK_ANSI_Y: return "Y"
            case kVK_ANSI_Z: return "Z"
            case kVK_ANSI_0: return "0"
            case kVK_ANSI_1: return "1"
            case kVK_ANSI_2: return "2"
            case kVK_ANSI_3: return "3"
            case kVK_ANSI_4: return "4"
            case kVK_ANSI_5: return "5"
            case kVK_ANSI_6: return "6"
            case kVK_ANSI_7: return "7"
            case kVK_ANSI_8: return "8"
            case kVK_ANSI_9: return "9"
            case kVK_F1: return "F1"
            case kVK_F2: return "F2"
            case kVK_F3: return "F3"
            case kVK_F4: return "F4"
            case kVK_F5: return "F5"
            case kVK_F6: return "F6"
            case kVK_F7: return "F7"
            case kVK_F8: return "F8"
            case kVK_F9: return "F9"
            case kVK_F10: return "F10"
            case kVK_F11: return "F11"
            case kVK_F12: return "F12"
            case kVK_Space: return "Space"
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Delete: return "⌫"
            case kVK_ForwardDelete: return "⌦"
            case kVK_UpArrow: return "↑"
            case kVK_DownArrow: return "↓"
            case kVK_LeftArrow: return "←"
            case kVK_RightArrow: return "→"
            case kVK_ANSI_Period: return "."
            case kVK_ANSI_Comma: return ","
            case kVK_ANSI_Slash: return "/"
            case kVK_ANSI_Backslash: return "\\"
            default: return "Key(\(rawValue))"
            }
        }

        var isFunctionKey: Bool {
            switch Int(rawValue) {
            case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                 kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - 3. Shortcut Value Type

    struct Shortcut: Codable, Equatable, Hashable, CustomStringConvertible {
        var key: Key
        private var modifierRawValue: UInt

        var modifiers: NSEvent.ModifierFlags {
            get {
                NSEvent.ModifierFlags(rawValue: modifierRawValue)
                    .intersection([.command, .option, .control, .shift])
            }
            set {
                modifierRawValue = newValue
                    .intersection([.command, .option, .control, .shift])
                    .rawValue
            }
        }

        init(_ key: Key, modifiers: NSEvent.ModifierFlags = []) {
            self.key = key
            self.modifierRawValue = modifiers
                .intersection([.command, .option, .control, .shift])
                .rawValue
        }

        var description: String {
            var parts: [String] = []
            let flags = modifiers
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            parts.append(key.displayString)
            return parts.joined(separator: " + ")
        }

        var displayString: String {
            description
        }
    }

    // MARK: - 4. Storage & Event Dispatch

    private static let userDefaultsPrefix = "7zip.KeyboardShortcuts."
    private static var defaultShortcuts: [String: Shortcut] = [:]
    private static var keyDownHandlers: [Name: [() -> Void]] = [:]
    private static var keyUpHandlers: [Name: [() -> Void]] = [:]
    private static var eventMonitorInstalled = false
    static var isRecordingShortcut = false

    static let didChangeNotification = Notification.Name("KeyboardShortcuts.didChangeNotification")

    private static func registerDefault(_ shortcut: Shortcut, for name: Name) {
        defaultShortcuts[name.rawValue] = shortcut
    }

    static func getShortcut(for name: Name) -> Shortcut? {
        let key = userDefaultsPrefix + name.rawValue
        if let data = UserDefaults.standard.data(forKey: key) {
            if data.isEmpty {
                // Explicitly cleared by user
                return nil
            }
            if let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
                return decoded
            }
        }
        return name.defaultShortcut ?? defaultShortcuts[name.rawValue]
    }

    static func setShortcut(_ shortcut: Shortcut?, for name: Name) {
        let key = userDefaultsPrefix + name.rawValue
        if let shortcut = shortcut, let encoded = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            // Store empty Data to indicate user explicitly cleared the shortcut
            UserDefaults.standard.set(Data(), forKey: key)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: name)
    }

    static func reset(_ names: Name...) {
        reset(names)
    }

    static func reset(_ names: [Name]) {
        for name in names {
            let key = userDefaultsPrefix + name.rawValue
            UserDefaults.standard.removeObject(forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: name)
        }
    }

    static func resetAll() {
        reset(Name.allCustomizable)
    }

    /// Registers a handler invoked when the user presses down the shortcut for `name`.
    static func onKeyDown(for name: Name, action: @escaping () -> Void) {
        ensureEventMonitorInstalled()
        keyDownHandlers[name] = [action]
    }

    /// Registers a handler invoked when the user releases the shortcut for `name`.
    static func onKeyUp(for name: Name, action: @escaping () -> Void) {
        ensureEventMonitorInstalled()
        keyUpHandlers[name] = [action]
    }

    /// Programmatically triggers all registered handlers for `name` (useful for tests and menu actions).
    static func trigger(_ name: Name) {
        for handler in keyDownHandlers[name] ?? [] {
            handler()
        }
        for handler in keyUpHandlers[name] ?? [] {
            handler()
        }
    }

    private static func ensureEventMonitorInstalled() {
        guard !eventMonitorInstalled else { return }
        eventMonitorInstalled = true

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard !isRecordingShortcut else { return event }

            // Avoid triggering single-key / shift-only shortcuts while typing in a text field unless Command/Control/Function key is used
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = Key(rawValue: event.keyCode)
            if let firstResponder = NSApp?.keyWindow?.firstResponder,
               firstResponder is NSTextView,
               flags.intersection([.command, .control]).isEmpty,
               !key.isFunctionKey {
                return event
            }

            let pressed = Shortcut(key, modifiers: flags)
            let table = (event.type == .keyDown) ? keyDownHandlers : keyUpHandlers

            var matched = false
            for (name, handlers) in table where !handlers.isEmpty {
                if let targetShortcut = getShortcut(for: name), targetShortcut == pressed {
                    matched = true
                    for handler in handlers {
                        handler()
                    }
                }
            }

            if matched && event.type == .keyDown {
                return nil
            }
            return event
        }
    }

    // MARK: - 5. SwiftUI Recorder View (`KeyboardShortcuts.Recorder`)

    struct Recorder: View {
        let title: String
        let name: Name
        let onChange: ((Shortcut?) -> Void)?

        @State private var currentShortcut: Shortcut?
        @State private var isRecording: Bool = false
        @State private var monitor: Any? = nil

        init(_ title: String = "", name: Name, onChange: ((Shortcut?) -> Void)? = nil) {
            self.title = title
            self.name = name
            self.onChange = onChange
            self._currentShortcut = State(initialValue: KeyboardShortcuts.getShortcut(for: name))
        }

        var body: some View {
            HStack(spacing: 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13))
                        .frame(width: 170, alignment: .leading)
                }

                Button(action: {
                    toggleRecording()
                }) {
                    HStack(spacing: 6) {
                        Text(buttonTitle)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(isRecording ? .accentColor : (currentShortcut == nil ? .secondary : .primary))
                            .frame(minWidth: 135, alignment: .center)

                        if currentShortcut != nil && !isRecording {
                            Button(action: {
                                clearShortcut()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Clear shortcut")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isRecording ? 1.5 : 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("ShortcutRecorder_\(name.rawValue)")

                if currentShortcut != name.defaultShortcut {
                    Button("Reset") {
                        KeyboardShortcuts.reset(name)
                        currentShortcut = KeyboardShortcuts.getShortcut(for: name)
                        onChange?(currentShortcut)
                    }
                    .font(.system(size: 11))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: KeyboardShortcuts.didChangeNotification)) { note in
                if let changedName = note.object as? Name, changedName == name {
                    currentShortcut = KeyboardShortcuts.getShortcut(for: name)
                }
            }
            .onDisappear {
                stopRecording()
            }
        }

        private var buttonTitle: String {
            if isRecording {
                return "Press shortcut..."
            }
            if let shortcut = currentShortcut {
                return shortcut.description
            }
            return "Record Shortcut"
        }

        private func toggleRecording() {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }

        private func clearShortcut() {
            stopRecording()
            KeyboardShortcuts.setShortcut(nil, for: name)
            currentShortcut = nil
            onChange?(nil)
        }

        private func startRecording() {
            isRecording = true
            KeyboardShortcuts.isRecordingShortcut = true

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = event.keyCode
                // Escape cancels recording
                if Int(keyCode) == kVK_Escape {
                    stopRecording()
                    return nil
                }

                // Ignore pure modifier presses
                if [kVK_Command, kVK_Shift, kVK_Option, kVK_Control, kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl, kVK_CapsLock].contains(Int(keyCode)) {
                    return nil
                }

                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

                // Backspace / Delete without modifiers clears the shortcut; with modifiers (e.g. ⌘ + ⌫) it records it
                if (Int(keyCode) == kVK_Delete || Int(keyCode) == kVK_ForwardDelete) && flags.isEmpty {
                    clearShortcut()
                    return nil
                }

                let key = Key(rawValue: keyCode)

                // Require at least one modifier (Command, Option, or Control) unless it's a Function key (F1-F12)
                guard !flags.intersection([.command, .option, .control]).isEmpty || key.isFunctionKey else {
                    NSSound.beep()
                    return nil
                }

                let recorded = Shortcut(key, modifiers: flags)
                KeyboardShortcuts.setShortcut(recorded, for: name)
                currentShortcut = recorded
                onChange?(recorded)
                stopRecording()
                return nil
            }
        }

        private func stopRecording() {
            isRecording = false
            KeyboardShortcuts.isRecordingShortcut = false
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
