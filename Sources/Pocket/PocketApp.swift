import SwiftUI

@main
struct PocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: workspace)
        }
        .defaultSize(width: 344, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Pocket") {
                Section("Presentation") {
                    Button("Device") {
                        workspace.presentationMode = .device
                    }
                    .keyboardShortcut("1", modifiers: [.command])

                    Button("Screen") {
                        workspace.presentationMode = .screen
                    }
                    .keyboardShortcut("2", modifiers: [.command])

                    Button("Workspace") {
                        workspace.presentationMode = .workspace
                    }
                    .keyboardShortcut("3", modifiers: [.command])
                }

                Section("Orientation") {
                    Button("Portrait") {
                        workspace.orientation = .portrait
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                    Button("Landscape") {
                        workspace.orientation = .landscape
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                }

                Section("Navigation") {
                    Button("Back") {
                        workspace.controller(for: workspace.selectedApp).goBack()
                    }
                    .keyboardShortcut("[", modifiers: [.command])

                    Button("Forward") {
                        workspace.controller(for: workspace.selectedApp).goForward()
                    }
                    .keyboardShortcut("]", modifiers: [.command])
                }

                Section("Window") {
                    Toggle("Always on Top", isOn: $workspace.alwaysOnTop)
                        .keyboardShortcut("t", modifiers: [.control, .option, .command])
                }
            }
        }
    }
}
