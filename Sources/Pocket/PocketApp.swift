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
                    .keyboardShortcut("1", modifiers: [.command])

                    Button("Screen") {
                        model.presentationMode = .screen
                    }
                    .keyboardShortcut("2", modifiers: [.command])

                }

                Section("Screens") {
                    ForEach(ScreenLayout.allCases) { layout in
                        Button(layout.title) {
                            model.screenLayout = layout
                            model.presentationMode = .screen
                        }
                    }
                }

                Section("Orientation") {
                    Button("Portrait") {
                        model.orientation = .portrait
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                    Button("Landscape") {
                        model.orientation = .landscape
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                }

                Section("Navigation") {
                    Button("Back") {
                        model.controller(for: model.selectedApp).goBack()
                    }
                    .keyboardShortcut("[", modifiers: [.command])

                    Button("Forward") {
                        model.controller(for: model.selectedApp).goForward()
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
