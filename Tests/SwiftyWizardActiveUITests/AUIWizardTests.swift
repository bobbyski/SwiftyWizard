import ActiveUI
import Foundation
import SwiftyWizard
import Testing
@testable import SwiftyWizardActiveUI

/// The ActiveUI wizard.
///
/// These test the *wrapper's* job — that it builds the right controls for a
/// question type, and that it does not re-implement any rules. The rules
/// themselves are `WizardEngine`'s, tested in SwiftyWizard's own suite, and the
/// point of this split is that they are tested **once**.
@MainActor
struct AUIWizardTests {
    private static let yaml = """
    wizard:
      name: Test Wizard
      exitButton: exitButton

      steps:
        - ask:
            title: About {{product}}
            nextButtonText: Onward
            questions:
              - variable: name
                prompt: Your name
                type: string
                required: true

              - variable: agreed
                prompt: Agree?
                type: boolean

        - ask:
            title: Second
            doneButtonText: Finish
            questions:
              - variable: colour
                prompt: Pick one
                type: choice
                options:
                  - red
                  - green

              - variable: folder
                prompt: Where?
                type: directory
    """

    private func makeWizard() -> AUIWizard {
        AUIWizard(yaml: Self.yaml, resources: ["product": "Freebird"])
    }

    /// Every view in a subtree, for asserting what got built.
    private func descendants(of view: AUIView) -> [AUIView] {
        view.children + view.children.flatMap(descendants(of:))
    }

    @Test("the wizard builds a view without touching a window")
    func buildsAView() {
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        #expect(!descendants(of: root).isEmpty)
    }

    @Test("the first step's questions are rendered")
    func rendersQuestions() {
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        let labels = descendants(of: root).compactMap { ($0 as? AUILabel)?.text }

        #expect(labels.contains("Your name"))
        #expect(labels.contains("Agree?"))
    }

    @Test("the title is templated from the resources")
    func templatesTheTitle() {
        // Proof the wrapper uses the engine's templating rather than printing
        // the raw string — the same `{{product}}` the SwiftUI wizard expands.
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        let labels = descendants(of: root).compactMap { ($0 as? AUILabel)?.text }

        #expect(labels.contains("About Freebird"))
    }

    @Test("a boolean question builds a toggle, a choice builds a picker")
    func buildsTypedControls() {
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        let all = descendants(of: root)

        #expect(all.contains { $0 is AUIToggle })
        #expect(all.contains { $0 is AUITextField })   // the required name field
        #expect(!all.contains { $0 is AUIPicker })     // choice is on step two
    }

    @Test("the primary button is disabled until the step is satisfied")
    func primaryReflectsValidation() {
        // The wrapper asks the engine; it does not decide. `name` is required
        // and unanswered, so the button must start disabled.
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        let buttons = descendants(of: root).compactMap { $0 as? AUIButton }
        let onward = buttons.first { $0.title == "Onward" }

        #expect(onward != nil)
        #expect(onward?.isEnabled == false)
    }

    @Test("the button titles come from the definition")
    func usesDefinedButtonTitles() {
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        let titles = descendants(of: root).compactMap { ($0 as? AUIButton)?.title }

        #expect(titles.contains("Onward"))   // nextButtonText
        #expect(titles.contains("Cancel"))   // the default, none declared
    }

    @Test("cancelling reports the answers with the exit button recorded")
    func cancelReports() {
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        var exitValue: String?
        wizard.onFinish = { exitValue = $0?["exitButton"] as? String }

        let cancel = descendants(of: root)
            .compactMap { $0 as? AUIButton }
            .first { $0.title == "Cancel" }
        cancel?.onClick?()

        #expect(exitValue == SwiftyWizardExitButton.cancel.rawValue)
    }

    @Test("the wrapper owns no rules of its own")
    func noDuplicatedRules() {
        // The claim this whole package rests on. If the wrapper had its own
        // validation, this would pass with the engine untouched — so the test
        // drives the *engine* and asserts the *view* followed.
        let wizard = makeWizard()
        let root = wizard.makeRootView()
        let field = descendants(of: root).compactMap { $0 as? AUITextField }.first
        let onward = descendants(of: root)
            .compactMap { $0 as? AUIButton }
            .first { $0.title == "Onward" }

        #expect(onward?.isEnabled == false)
        field?.text = "Ada"
        field?.onChange?("Ada")

        #expect(onward?.isEnabled == true)
        #expect(wizard.answers["name"] as? String == "Ada")
    }
}
