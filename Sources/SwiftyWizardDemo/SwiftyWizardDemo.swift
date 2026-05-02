import SwiftUI
import SwiftyWizard
import AppKit

@main
struct SwiftyWizardDemoApp: App {
    @NSApplicationDelegateAdaptor(SwiftyWizardDemoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SwiftyWizardDemoWindow()
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}

private final class SwiftyWizardDemoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.mainMenu = makeMainMenu()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "About SwiftyWizardDemo",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )

        appMenu.addItem(.separator())

        let servicesMenu = NSMenu(title: "Services")
        NSApplication.shared.servicesMenu = servicesMenu
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(.separator())

        appMenu.addItem(
            withTitle: "Hide SwiftyWizardDemo",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )

        let hideOthersItem = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )

        appMenu.addItem(.separator())

        appMenu.addItem(
            withTitle: "Quit SwiftyWizardDemo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return mainMenu
    }
}

private struct SwiftyWizardDemoWindow: View {
    @State private var output: [String: Any?] = [:]

    var body: some View {
        SwiftyWizardView(
            wizardDef: """
            wizard:
              name: My new Swift wizard
              language: Swift
              category: Business
              exitButton: exit

              steps:
                - ask:
                    title: Create Project
                    background: background.png
                    icon: headerImage.png
                    cancelButtonText: Cancel
                    nextButtonText: Next
                    questions:
                      - variable: project_name
                        prompt: What is the name of your project?
                        help: This is the name of the application's executable.
                        type: string
                        required: true
                        default: My Great App

                      - variable: project_folder
                        prompt: Where should we create your {{project_name}} project?
                        help: This is the location where the project will be built.
                        type: directory
                        required: true

                - ask:
                    title: Copyright
                    backgroundColor: #555580
                    cancelButtonText: Cancel
                    backButtonText: Back
                    doneButtonText: OK
                    questions:
                      - variable: author
                        prompt: Who is the copy right holder?
                        help: this is the owner of the IP
                        type: string

                - do:
                    internal: build_string
                    variable: copyrigth_notice
                    from: "Copyriight {{current_year}} {{author}}, All rights reserved"

                - do:
                    name: create project_name
                    command: mkdir {{project_folder}}/{{project_name}}

                - do:
                    name: update project files
                    internal: replaceVariables
            """,
            resources: ["current_year": 2026],
            output: $output
        )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Quit SwiftyWizardDemo") {
                            NSApplication.shared.terminate(nil)
                        }
                        .keyboardShortcut("q")
                    } label: {
                        Label("App", systemImage: "app")
                    }
                }
            }
    }
}
