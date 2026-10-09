import SwiftUI

@main
struct PocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = PocketModel.shared
    @ObservedObject private var bindings = KeyBindingStore.shared

    var body: some Scene {
        // AppDelegate owns the floating panel; SwiftUI supplies the app menus.
        Settings {
            PocketSettingsView(model: model)
        }
        .defaultSize(width: 840, height: 580)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    bindings.perform(.settings)
                }
                .pocketShortcut(bindings.chord(for: .settings))
            }

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
                        bindings.perform(.portrait)
                    }
                    .pocketShortcut(bindings.chord(for: .portrait))

                    Button("Landscape") {
                        bindings.perform(.landscape)
                    }
                    .pocketShortcut(bindings.chord(for: .landscape))
                }

                Section("Screens") {
                    ForEach(PocketCommand.allCases.filter { $0.screenCount != nil }) { command in
                        Button(command.title) {
                            bindings.perform(command)
                        }
                        .pocketShortcut(bindings.chord(for: command))
                    }
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
                        model.settingsSection = .websites
                        model.isSettingsPresented = true
                        WindowManager.shared.showSettings()
                    }

                    Button(BrowserSessionImporter.buttonTitle()) {
                        model.isBrowserImportPresented = true
                    }
                }
            }
        }
    }
}
