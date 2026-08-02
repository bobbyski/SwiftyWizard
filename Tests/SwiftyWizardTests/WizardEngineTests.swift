import Foundation
import Testing
@testable import SwiftyWizard

/// The wizard's rules, tested for the first time.
///
/// They were untestable before — parsing, validation, navigation and templating
/// all lived inside a 774-line SwiftUI view, expressed as `@State` and
/// `Binding`s. Extracting `WizardEngine` was mostly about letting a second UI
/// framework render the same wizard, but this is the other half of the payoff:
/// the rules can now be stated and checked without drawing anything.
@MainActor
struct WizardEngineTests {
    /// The real schema, taken from the demo — `wizard:` root, `steps:` with
    /// `- ask:` blocks. My first fixture invented a flatter shape and parsed to
    /// zero steps, which is a good argument for a test that reads the format
    /// the product actually ships.
    private static let yaml = """
    wizard:
      name: Test Wizard
      exitButton: exitButton

      steps:
        - ask:
            title: First
            nextButtonText: Onward
            questions:
              - variable: name
                prompt: Your name
                type: string
                required: true

              - variable: count
                prompt: How many
                type: number
                default: 3

        - ask:
            title: Second
            doneButtonText: Finish
            questions:
              - variable: agreed
                prompt: Agree?
                type: boolean

              - variable: colour
                prompt: Pick one
                type: choice
                options:
                  - red
                  - green
    """

    private func makeEngine(resources: [String: Any?] = [:]) -> WizardEngine {
        WizardEngine(yaml: Self.yaml, resources: resources)
    }

    // MARK: - Parsing

    @Test("the definition parses into steps and questions")
    func parses() {
        let engine = makeEngine()
        #expect(engine.definition.name == "Test Wizard")
        #expect(engine.definition.askSteps.count == 2)
        #expect(engine.definition.askSteps.first?.questions.count == 2)
        #expect(engine.definition.exitButtonVariable == "exitButton")
    }

    @Test("question types map from their aliases")
    func questionTypeAliases() {
        // The YAML author writes "int" or "bool"; the engine should not care.
        #expect(WizardQuestionType(rawValue: "int") == .number)
        #expect(WizardQuestionType(rawValue: "bool") == .boolean)
        #expect(WizardQuestionType(rawValue: "picker") == .choice)
        #expect(WizardQuestionType(rawValue: "folder") == .directory)
        #expect(WizardQuestionType(rawValue: "nonsense") == .string)
    }

    // MARK: - Defaults

    @Test("declared defaults are seeded at construction")
    func seedsDefaults() {
        let engine = makeEngine()
        #expect(engine.stringValue(for: "count") == "3")
    }

    @Test("a default never overwrites an answer")
    func defaultsDoNotClobber() {
        // The reason defaults are applied once: a redraw must not undo typing.
        let engine = makeEngine()
        engine.setValue("typed", for: "count")
        #expect(engine.stringValue(for: "count") == "typed")
    }

    // MARK: - Validation

    @Test("a required question blocks leaving the step")
    func requiredBlocks() {
        let engine = makeEngine()
        #expect(engine.canLeaveCurrentStep == false)
        #expect(engine.next() == false)
        #expect(engine.currentStepIndex == 0)
    }

    @Test("whitespace does not satisfy a required question")
    func whitespaceIsNotAnAnswer() {
        let engine = makeEngine()
        engine.setValue("   ", for: "name")
        #expect(engine.canLeaveCurrentStep == false)
    }

    @Test("answering the required question unblocks the step")
    func answeringUnblocks() {
        let engine = makeEngine()
        engine.setValue("Ada", for: "name")
        #expect(engine.canLeaveCurrentStep)
        #expect(engine.next())
        #expect(engine.currentStepIndex == 1)
    }

    // MARK: - Navigation

    @Test("back stops at the first step")
    func backClamps() {
        let engine = makeEngine()
        engine.back()
        #expect(engine.currentStepIndex == 0)
        #expect(engine.canGoBack == false)
    }

    @Test("the last step is reported as last")
    func lastStep() {
        let engine = makeEngine()
        #expect(engine.isLastStep == false)
        engine.setValue("Ada", for: "name")
        engine.next()
        #expect(engine.isLastStep)
        #expect(engine.canGoBack)
    }

    // MARK: - Finishing

    @Test("done is refused while the step is unsatisfied")
    func doneRefusedWhenInvalid() {
        // The engine will not let a host close a wizard it would not let you
        // leave — the check lives in one place rather than in each wrapper.
        let engine = makeEngine()
        #expect(engine.finish(.done) == nil)
    }

    @Test("cancel is always allowed")
    func cancelAlwaysAllowed() {
        let engine = makeEngine()
        let answers = engine.finish(.cancel)
        #expect(answers != nil)
        #expect(answers?["exitButton"] as? String == SwiftyWizardExitButton.cancel.rawValue)
    }

    @Test("done records the exit button and returns the answers")
    func doneReturnsAnswers() {
        let engine = makeEngine()
        engine.setValue("Ada", for: "name")
        let answers = engine.finish(.done)
        #expect(answers?["exitButton"] as? String == SwiftyWizardExitButton.done.rawValue)
        #expect(answers?["name"] as? String == "Ada")
    }

    // MARK: - Value coercion

    @Test("numeric text is coerced to a number")
    func coercesNumbers() {
        let engine = makeEngine()
        let question = engine.definition.askSteps[0].questions[1]
        engine.setText("42", for: question)
        #expect(engine.answers["count"] as? Int == 42)
    }

    @Test("half-typed numbers are kept as text rather than discarded")
    func keepsPartialInput() {
        // Typing "4" on the way to "4.5" must not be rejected mid-keystroke.
        let engine = makeEngine()
        let question = engine.definition.askSteps[0].questions[1]
        engine.setText("4x", for: question)
        #expect(engine.stringValue(for: "count") == "4x")
    }

    @Test("boolean answers accept the strings a YAML author writes")
    func booleanStrings() {
        let engine = makeEngine()
        engine.setValue("yes", for: "agreed")
        #expect(engine.boolValue(for: "agreed"))
        engine.setValue("no", for: "agreed")
        #expect(engine.boolValue(for: "agreed") == false)
        engine.setValue(true, for: "agreed")
        #expect(engine.boolValue(for: "agreed"))
    }

    // MARK: - Templating

    @Test("a token resolves from the answers")
    func templateFromAnswers() {
        let engine = makeEngine()
        engine.setValue("Ada", for: "name")
        #expect(engine.renderTemplate("Hello {{name}}") == "Hello Ada")
    }

    @Test("a token resolves from the resources")
    func templateFromResources() {
        let engine = makeEngine(resources: ["product": "Freebird"])
        #expect(engine.renderTemplate("Welcome to {{product}}") == "Welcome to Freebird")
    }

    @Test("an unresolved token stays visible")
    func unresolvedTokenIsVisible() {
        // Deliberate: a missing value should be obvious on screen, not an empty
        // gap nobody notices.
        let engine = makeEngine()
        #expect(engine.renderTemplate("Hi {{missing}}") == "Hi {{Missing}}")
    }

    @Test("an unterminated token is left alone")
    func unterminatedToken() {
        let engine = makeEngine()
        #expect(engine.renderTemplate("Broken {{name") == "Broken {{name")
    }

    // MARK: - Host notification

    @Test("changes are announced to a retained host")
    func announcesChanges() {
        let engine = makeEngine()
        var fired = 0
        engine.onChange = { fired += 1 }

        engine.setValue("Ada", for: "name")
        engine.next()
        engine.back()

        #expect(fired == 3)
    }
}
