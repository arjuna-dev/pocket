import AppKit
import SwiftUI

enum PocketMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func fade(_ reduceMotion: Bool, duration: TimeInterval = 0.16) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }

    static func fade(duration: TimeInterval = 0.16) -> Animation? {
        fade(reduceMotion, duration: duration)
    }
}

struct ChromeControlFocusedKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Keeps chrome in the accessibility tree while it is visually faded.
    /// Mouse hits pass through until the bar is actually shown.
    func pocketFade(_ shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .accessibilityHidden(false)
            .allowsHitTesting(shown)
    }

    func chromeControl(label: String, hint: String? = nil, value: String? = nil, interactive: Bool = true) -> some View {
        modifier(ChromeControlModifier(label: label, hint: hint, value: value, interactive: interactive))
    }

    @ViewBuilder
    func accessibilityActionIf(_ condition: Bool, _ name: String, action: @escaping () -> Void) -> some View {
        if condition {
            self.accessibilityAction(named: name, action)
        } else {
            self
        }
    }

    @ViewBuilder
    func focusedScreenAccessibility(title: String, isFocused: Bool, announceFocus: Bool) -> some View {
        if announceFocus {
            let pane = self
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
            if isFocused {
                pane.accessibilityValue("Focused")
            } else {
                pane
            }
        } else {
            self
        }
    }
}

private struct ChromeControlModifier: ViewModifier {
    let label: String
    var hint: String?
    var value: String?
    var interactive: Bool
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .accessibilityFocused($accessibilityFocused)
            .preference(key: ChromeControlFocusedKey.self, value: focused || accessibilityFocused)
            .accessibilityRespondsToUserInteraction(interactive)
            .accessibilityLabel(label)
            .modifier(ChromeHintModifier(hint: hint))
            .modifier(ChromeValueModifier(value: value))
    }
}

private struct ChromeHintModifier: ViewModifier {
    let hint: String?

    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

private struct ChromeValueModifier: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}
