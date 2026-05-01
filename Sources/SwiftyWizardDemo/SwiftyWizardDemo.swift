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
    var body: some View {
        SwiftyWizardView()
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
