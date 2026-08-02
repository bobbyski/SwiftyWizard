import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Entry point for running a wizard as a modal SwiftUI flow.
public final class SwiftyWizard {
    private init() {}

    #if os(macOS)
    /// Presents a wizard and returns the values collected from its questions.
    ///
    /// - Parameters:
    ///   - wizardDef: YAML text that describes the wizard.
    ///   - resources: Optional named resources, such as images, available to the wizard.
    ///   - size: The size of the modal wizard content. Defaults to 500 x 350.
    ///   - view: Optional host view. When provided, the wizard is presented as a sheet on that view's window.
    /// - Returns: The output dictionary collected by the wizard.
    @MainActor
    public static func runWizard(
        wizardDef: String,
        resources: [String: Any?] = [:],
        size: CGSize = CGSize(width: 500, height: 350),
        view: NSView? = nil
    ) async -> [String: Any?] {
        await withCheckedContinuation { continuation in
            let session = SwiftyWizardModalSession(continuation: continuation)
            let window = SwiftyWizardModalWindow(
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

            // Keep the session alive while AppKit owns the modal window.
            SwiftyWizardModalSession.retain(session, for: window)

            if let parentWindow = view?.window {
                session.parentWindow = parentWindow
                parentWindow.beginSheet(window)
                window.makeKey()
            } else {
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.runModal(for: window)
            }
        }
    }
    #else
    /// Placeholder for non-macOS platforms until platform-specific presentation is added.
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
/// Borderless windows do not become key by default, but text fields need a key window for focus.
private final class SwiftyWizardModalWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

/// Hosts a `SwiftyWizardView` with local output state for modal presentation.
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
    // AppKit window delegates are weak, so the active session is retained here by window identity.
    private static var retainedSessions: [ObjectIdentifier: SwiftyWizardModalSession] = [:]

    private var continuation: CheckedContinuation<[String: Any?], Never>?
    weak var window: NSWindow?
    weak var parentWindow: NSWindow?

    init(continuation: CheckedContinuation<[String: Any?], Never>) {
        self.continuation = continuation
    }

    /// Closes the modal or sheet and resumes the async `runWizard` caller once.
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

        // `[String: Any?]` cannot be proven `Sendable` — the values are `Any`,
        // so they might be anything — and `withCheckedContinuation` erases the
        // isolation that would otherwise make this safe. Both ends *are* the
        // main actor here: this method is `@MainActor` and so is `runWizard`,
        // whose caller receives the value. The hand-off is annotated rather
        // than the API weakened, because typing the answers as `Sendable` would
        // change the public contract for every existing wizard.
        nonisolated(unsafe) let answers = output
        continuation.resume(returning: answers)
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
