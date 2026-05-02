import SwiftUI

#if os(macOS)
import AppKit
#endif

public final class SwiftyWizard {
    private init() {}

    #if os(macOS)
    @MainActor
    public static func runWizard(
        wizardDef: String,
        resources: [String: Any?] = [:],
        size: CGSize = CGSize(width: 500, height: 350),
        view: NSView? = nil
    ) async -> [String: Any?] {
        await withCheckedContinuation { continuation in
            let session = SwiftyWizardModalSession(continuation: continuation)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            session.window = window
            window.delegate = session
            window.isReleasedWhenClosed = false
            window.setContentSize(size)
            window.minSize = window.frame.size
            window.maxSize = window.frame.size
            window.contentViewController = NSHostingController(
                rootView: SwiftyWizardModalView(
                    wizardDef: wizardDef,
                    resources: resources,
                    size: size,
                    onExit: session.finish
                )
            )

            SwiftyWizardModalSession.retain(session, for: window)

            if let parentWindow = view?.window {
                session.parentWindow = parentWindow
                parentWindow.beginSheet(window)
            } else {
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.runModal(for: window)
            }
        }
    }
    #else
    @MainActor
    public static func runWizard(
        wizardDef: String,
        resources: [String: Any?] = [:],
        size: CGSize = CGSize(width: 500, height: 350)
    ) async -> [String: Any?] {
        [:]
    }
    #endif
}

#if os(macOS)
private struct SwiftyWizardModalView: View {
    let wizardDef: String
    let resources: [String: Any?]
    let size: CGSize
    let onExit: ([String: Any?]) -> Void

    @State private var output: [String: Any?] = [:]

    var body: some View {
        SwiftyWizardView(
            wizardDef: wizardDef,
            resources: resources,
            output: $output,
            onExit: onExit
        )
        .frame(width: size.width, height: size.height)
    }
}

@MainActor
private final class SwiftyWizardModalSession: NSObject, NSWindowDelegate {
    private static var retainedSessions: [ObjectIdentifier: SwiftyWizardModalSession] = [:]

    private var continuation: CheckedContinuation<[String: Any?], Never>?
    weak var window: NSWindow?
    weak var parentWindow: NSWindow?

    init(continuation: CheckedContinuation<[String: Any?], Never>) {
        self.continuation = continuation
    }

    func finish(_ output: [String: Any?]) {
        guard let continuation else {
            return
        }

        self.continuation = nil

        if let window, let parentWindow {
            parentWindow.endSheet(window)
        } else {
            NSApplication.shared.stopModal()
            window?.close()
        }

        continuation.resume(returning: output)
        release()
    }

    func windowWillClose(_ notification: Notification) {
        finish([:])
    }

    static func retain(_ session: SwiftyWizardModalSession, for window: NSWindow) {
        retainedSessions[ObjectIdentifier(window)] = session
    }

    private func release() {
        guard let window else {
            return
        }

        Self.retainedSessions.removeValue(forKey: ObjectIdentifier(window))
    }
}
#endif
