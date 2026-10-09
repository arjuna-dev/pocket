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
                    .disabled(model.activeSlot == nil)

                    Button("Forward") {
                        model.activeSlot?.controller.goForward()
                    }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(model.activeSlot == nil)

                    Button("Reload") {
                        model.activeSlot?.controller.reloadPage()
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.activeSlot == nil)
                }

                Section("Window") {
                    Toggle("Always on Top", isOn: $model.alwaysOnTop)
                        .keyboardShortcut("t", modifiers: [.control, .option, .command])

                    Button("Add Screen to the Right") {
                        if let slot = model.activeSlot {
                            model.split(slot, at: .trailing)
                        }
                    }
                    .disabled(model.activeSlot == nil || model.paneLayout.root.gridSpan.columns != 1)

                    Button("Add Screen Below") {
                        if let slot = model.activeSlot {
                            model.split(slot, at: .bottom)
                        }
                    }
                    .disabled(model.activeSlot == nil || model.paneLayout.root.gridSpan.rows != 1)

                    Button("Remove Screen") {
                        model.isScreenRemovalPresented = true
                    }
                    .disabled(model.paneLayout.leafCount < 2)
                }

                Section("Sites") {
                    Button("Switch Site") {
                        model.isSiteMenuPresented = true
                    }
                    .disabled(model.activeSlot == nil)

                    Button("Manage Sites") {
                        model.isWebsiteManagerPresented = true
                    }

                    Button(BrowserSessionImporter.buttonTitle()) {
                        model.isBrowserImportPresented = true
                    }
                }
            }
        }
    }
}
