import AppKit
import SwiftUI

enum PocketCommand: String, CaseIterable, Identifiable {
    case portrait
    case landscape
    case oneScreen
    case twoScreens
    case threeScreens
    case fourScreens
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        case .oneScreen: return "One Screen"
        case .twoScreens: return "Two Screens"
        case .threeScreens: return "Three Screens"
        case .fourScreens: return "Four Screens"
        case .settings: return "Settings"
        }
    }

    var screenCount: Int? {
        switch self {
        case .oneScreen: return 1
        case .twoScreens: return 2
        case .threeScreens: return 3
        case .fourScreens: return 4
        default: return nil
        }
    }
}

struct KeyChord: Codable, Equatable, Hashable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)
        guard command || option || control else { return nil }
        guard let key = Self.key(from: event) else { return nil }
        self.init(key: key, command: command, shift: shift, option: option, control: control)
    }

    var symbols: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        text += label
        return text
    }

    var spoken: String {
        var parts: [String] = []
        if control { parts.append("Control") }
        if option { parts.append("Option") }
        if shift { parts.append("Shift") }
        if command { parts.append("Command") }
        parts.append(spokenKey)
        return parts.joined(separator: " ")
    }

    var keyEquivalent: KeyEquivalent? {
        guard key.count == 1, let character = key.first else { return nil }
        return KeyEquivalent(character)
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return modifiers
    }

    private var label: String {
        if key == "," { return "," }
        if key.count == 1, let character = key.first, character.isLetter {
            return key.uppercased()
        }
        return key
    }

    private var spokenKey: String {
        switch key {
        case ",": return "Comma"
        case ".": return "Period"
        case "/": return "Slash"
        case "\\": return "Backslash"
        case "[": return "Left Bracket"
        case "]": return "Right Bracket"
        case ";": return "Semicolon"
        case "'": return "Quote"
        case " ": return "Space"
        default:
            return key.uppercased()
        }
    }

    private static func key(from event: NSEvent) -> String? {
        if event.keyCode == 53 { return nil }
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(event.keyCode) { return nil }
        guard let raw = event.charactersIgnoringModifiers, raw.count == 1 else { return nil }
        guard let scalar = raw.unicodeScalars.first, scalar.value >= 32 else { return nil }
        return raw.lowercased()
    }
}

final class KeyBindingStore: ObservableObject {
    static let shared = KeyBindingStore()

    @Published private(set) var chords: [PocketCommand: KeyChord]
    @Published var recording: PocketCommand?

    private var monitor: Any?
    private static let storageKey = "Pocket.keyBindings"

    private init() {
        chords = Self.load()
    }

    func chord(for command: PocketCommand) -> KeyChord {
        chords[command] ?? Self.defaults[command] ?? KeyChord(key: "", command: true)
    }

    func beginRecording(_ command: PocketCommand) {
        recording = recording == command ? nil : command
    }

    func assign(_ chord: KeyChord, to command: PocketCommand) {
        if let other = chords.first(where: { $0.key != command && $0.value == chord })?.key {
            chords[other] = chords[command] ?? Self.defaults[command]
        }
        chords[command] = chord
        recording = nil
        persist()
    }

    func perform(_ command: PocketCommand) {
        let model = PocketModel.shared
        switch command {
        case .portrait:
            model.orientation = .portrait
        case .landscape:
            model.orientation = .landscape
        case .oneScreen, .twoScreens, .threeScreens, .fourScreens:
            if let count = command.screenCount {
                model.showScreenCount(count)
            }
        case .settings:
            if model.isSettingsPresented {
                recording = nil
                model.isSettingsPresented = false
            } else {
                WindowManager.shared.showSettings()
            }
        }
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.isARepeat { return event }
        if recording != nil, !PocketModel.shared.isSettingsPresented {
            recording = nil
        }
        if recording != nil {
            if event.keyCode == 53 {
                recording = nil
                return nil
            }
            guard let chord = KeyChord(event: event), let recording else {
                NSSound.beep()
                return nil
            }
            assign(chord, to: recording)
            return nil
        }
        guard let command = chords.first(where: { KeyChord(event: event) == $0.value })?.key else {
            return event
        }
        perform(command)
        return nil
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: chords.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [PocketCommand: KeyChord] {
        var chords = defaults
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: KeyChord].self, from: data) else {
            return chords
        }
        for (rawValue, chord) in stored {
            guard let command = PocketCommand(rawValue: rawValue), !chord.key.isEmpty else { continue }
            chords[command] = chord
        }
        return chords
    }

    private static let defaults: [PocketCommand: KeyChord] = [
        .portrait: KeyChord(key: "1", command: true),
        .landscape: KeyChord(key: "2", command: true),
        .oneScreen: KeyChord(key: "3", command: true),
        .twoScreens: KeyChord(key: "4", command: true),
        .threeScreens: KeyChord(key: "5", command: true),
        .fourScreens: KeyChord(key: "6", command: true),
        .settings: KeyChord(key: ",", command: true)
    ]
}

extension View {
    @ViewBuilder
    func pocketShortcut(_ chord: KeyChord) -> some View {
        if let key = chord.keyEquivalent {
            self.keyboardShortcut(key, modifiers: chord.eventModifiers)
        } else {
            self
        }
    }
}
