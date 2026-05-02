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
        size: CGSize = CGSize(width: 400, height: 350)
    ) async -> [String: Any?] {
        await withCheckedContinuation { continuation in
            let session = SwiftyWizardModalSession(continuation: continuation)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            session.window = window
            window.delegate = session
            window.title = "SwiftyWizard"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SwiftyWizardModalView(
                    wizardDef: wizardDef,
                    resources: resources,
                    onExit: session.finish
                )
            )
            window.center()
            window.makeKeyAndOrderFront(nil)

            SwiftyWizardModalSession.retain(session, for: window)
            NSApplication.shared.runModal(for: window)
        }
    }
    #else
    @MainActor
    public static func runWizard(
        wizardDef: String,
        resources: [String: Any?] = [:],
        size: CGSize = CGSize(width: 400, height: 350)
    ) async -> [String: Any?] {
        [:]
    }
    #endif
}

#if os(macOS)
private struct SwiftyWizardModalView: View {
    let wizardDef: String
    let resources: [String: Any?]
    let onExit: ([String: Any?]) -> Void

    @State private var output: [String: Any?] = [:]

    var body: some View {
        SwiftyWizardView(
            wizardDef: wizardDef,
            resources: resources,
            output: $output,
            onExit: onExit
        )
    }
}

@MainActor
private final class SwiftyWizardModalSession: NSObject, NSWindowDelegate {
    private static var retainedSessions: [ObjectIdentifier: SwiftyWizardModalSession] = [:]

    private var continuation: CheckedContinuation<[String: Any?], Never>?
    weak var window: NSWindow?

    init(continuation: CheckedContinuation<[String: Any?], Never>) {
        self.continuation = continuation
    }

    func finish(_ output: [String: Any?]) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        NSApplication.shared.stopModal()
        window?.close()
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
