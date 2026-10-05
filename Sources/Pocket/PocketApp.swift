import SwiftUI

@main
struct PocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = PocketModel.shared

    var body: some Scene {
        // AppDelegate owns the floating panel; SwiftUI supplies the app menus.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
            CommandMenu("Pocket") {
                Section("Presentation") {
                    Button("Device") {
                        model.presentationMode = .device
                    }

                    Button("Screen") {
                        model.presentationMode = .screen
                    }
                }

                Section("Orientation") {
                    Button("Portrait") {
                        model.orientation = .portrait
                    }
                    .keyboardShortcut("1", modifiers: [.command])

                    Button("Landscape") {
                        model.orientation = .landscape
                    }
                    .keyboardShortcut("2", modifiers: [.command])
                }

                Section("Navigation") {
                    Button("Back") {
                        model.activeSlot?.controller.goBack()
                    }
                    .keyboardShortcut("[", modifiers: [.command])

                    Button("Forward") {
                        model.activeSlot?.controller.goForward()
                    }
                    .keyboardShortcut("]", modifiers: [.command])
                }

                Section("Window") {
                    Toggle("Always on Top", isOn: $model.alwaysOnTop)
                        .keyboardShortcut("t", modifiers: [.control, .option, .command])
                }
            }
        }
    }
}
