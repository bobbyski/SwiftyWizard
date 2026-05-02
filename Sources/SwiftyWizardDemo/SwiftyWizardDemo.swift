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

/// Installs a small standard app menu for the SwiftPM-launched macOS demo app.
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
    @State private var renderedDoSteps = ""
    @State private var hostView: NSView?

    private var resources: [String: Any?] {
        var resources: [String: Any?] = ["current_year": 2026]

        // The wizard references images by filename, so those filenames are the resource keys.
        for filename in ["headerImage.png", "background.png"] {
            resources[filename] = loadImageResource(named: filename)
        }

        return resources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Run Wizard") {
                Task {
                    let output = await SwiftyWizard.runWizard(
                        wizardDef: demoWizardDef,
                        resources: resources,
                        view: hostView
                    )
                    renderedDoSteps = renderDoSteps(from: demoWizardDef, output: output)
                }
            }

            TextEditor(text: $renderedDoSteps)
                .font(.system(.body, design: .monospaced))
                .border(.secondary.opacity(0.35))
        }
        .padding(16)
        .background(ViewResolver { view in
            hostView = view
        })
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

    private var demoWizardDef: String {
        """
        wizard:
          name: My new Swift wizard
          language: Swift
          category: Business
          exitButton: exit

          steps:
            - ask:
                title: Create Project
                headerImage: headerImage.png
                cancelButtonText: Cancel the wizard
                nextButtonText: Next page
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
                background: background.png
                backgroundAlpha: 30%
                headerImage: headerImage.png
                backgroundColor: #555580
                cancelButtonText: Cancel
                backButtonText: Back to previous
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
        """
    }

    private func renderDoSteps(from wizardDef: String, output: [String: Any?]) -> String {
        extractDoSteps(from: wizardDef)
            .map { renderTemplate($0, output: output) }
            .joined(separator: "\n\n")
    }

    private func extractDoSteps(from wizardDef: String) -> [String] {
        let lines = wizardDef
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { DemoParsedLine(raw: String($0)) }

        var steps: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            guard line.text == "- do:" else {
                index += 1
                continue
            }

            let startIndex = index
            index += 1

            // A `do` block ends at the next sibling list item in the `steps` array.
            while index < lines.count {
                let nextLine = lines[index]
                if nextLine.indent == line.indent && nextLine.text.hasPrefix("- ") {
                    break
                }
                index += 1
            }

            steps.append(
                lines[startIndex..<index]
                    .map(\.raw)
                    .joined(separator: "\n")
            )
        }

        return steps
    }

    private func renderTemplate(_ text: String, output: [String: Any?]) -> String {
        var rendered = ""
        var remainder = text[...]

        while let startRange = remainder.range(of: "{{") {
            rendered += remainder[..<startRange.lowerBound]

            let afterStart = remainder[startRange.upperBound...]
            guard let endRange = afterStart.range(of: "}}") else {
                rendered += remainder[startRange.lowerBound...]
                return rendered
            }

            let key = String(afterStart[..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            rendered += templateValue(for: key, output: output) ?? "{{\(key.capitalized)}}"
            remainder = afterStart[endRange.upperBound...]
        }

        rendered += remainder
        return rendered
    }

    private func templateValue(for key: String, output: [String: Any?]) -> String? {
        if let outputValue = output[key] ?? nil {
            return String(describing: outputValue)
        }

        if let resourceValue = resources[key] ?? nil {
            return String(describing: resourceValue)
        }

        return nil
    }

    private func loadImageResource(named filename: String) -> NSImage? {
        let url = Bundle.module.url(
            forResource: (filename as NSString).deletingPathExtension,
            withExtension: (filename as NSString).pathExtension
        )

        guard let url else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private struct DemoParsedLine {
    var raw: String
    var indent: Int
    var text: String

    init(raw: String) {
        self.raw = raw
        self.indent = raw.prefix { $0 == " " }.count
        self.text = raw.trimmingCharacters(in: .whitespaces)
    }
}

/// Reads the current AppKit view so the demo can present the wizard as a sheet.
private struct ViewResolver: NSViewRepresentable {
    var onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            onResolve(view)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}
