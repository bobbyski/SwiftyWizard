import Foundation

/// A running wizard: the answers so far, where you are, and what you may do next.
///
/// **This was the other half of `SwiftyWizardView`.** Validation, navigation,
/// defaults, value coercion and `{{template}}` rendering all lived inside a
/// SwiftUI struct, expressed as `Binding`s and `@State`. None of it is about
/// drawing — it is what a wizard *is* — so it is here, and the views became
/// renderers over it.
///
/// **Report, don't perform.** The engine never presents a file picker, never
/// closes a window and never decides what a button looks like. It says what the
/// current step is, whether you may leave it, and what the answers are; the host
/// does the rest. That is what lets one engine serve a SwiftUI sheet and an
/// ActiveUI window without either one leaking into it.
///
///     let engine = WizardEngine(yaml: definition, resources: resources)
///     engine.setValue("Ada", for: "name")
///     if engine.canLeaveCurrentStep { engine.next() }
///     let answers = engine.finish(.done)
@MainActor
public final class WizardEngine {
    /// The parsed definition.
    public let definition: WizardDefinition

    /// Named values supplied by the host — images, and anything a `{{token}}`
    /// might resolve to.
    public let resources: [String: Any?]

    /// Answers collected so far, keyed by question variable.
    public private(set) var answers: [String: Any?] = [:]

    /// Which step is showing.
    public private(set) var currentStepIndex = 0

    /// Called after any change, for hosts that cannot observe.
    ///
    /// The same plain-closure seam the rest of this project uses: a retained
    /// host has nothing to subscribe with, and refreshing on a guess is worse
    /// than being told.
    public var onChange: (() -> Void)?

    /// Creates an engine from YAML.
    public init(yaml: String, resources: [String: Any?] = [:]) {
        self.definition = WizardDefinitionParser.parse(yaml)
        self.resources = resources
        applyDefaults()
    }

    /// Creates an engine from an already-parsed definition.
    public init(definition: WizardDefinition, resources: [String: Any?] = [:]) {
        self.definition = definition
        self.resources = resources
        applyDefaults()
    }

    // MARK: - Where we are

    /// The step being shown, or nil for a wizard with no steps.
    public var currentStep: WizardAskStep? {
        guard definition.askSteps.indices.contains(currentStepIndex) else { return nil }
        return definition.askSteps[currentStepIndex]
    }

    /// Whether there is a step before this one.
    public var canGoBack: Bool { currentStepIndex > 0 }

    /// Whether this is the last step — the one whose primary button is *Done*.
    public var isLastStep: Bool { currentStepIndex >= definition.askSteps.count - 1 }

    /// Whether every required question on this step has an answer.
    ///
    /// A required question answered with whitespace counts as unanswered, which
    /// is the behaviour a user expects and the reason this is not just a nil
    /// check.
    public var canLeaveCurrentStep: Bool {
        guard let step = currentStep else { return true }
        return step.questions.allSatisfy { question in
            guard question.required else { return true }
            switch answers[question.variable] ?? nil {
            case let value as String:
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .some:
                return true
            case .none:
                return false
            }
        }
    }

    // MARK: - Moving

    /// Goes back one step. No-op on the first.
    public func back() {
        currentStepIndex = max(0, currentStepIndex - 1)
        onChange?()
    }

    /// Advances one step, if the current one is satisfied.
    /// - Returns: Whether it moved.
    @discardableResult
    public func next() -> Bool {
        guard canLeaveCurrentStep else { return false }
        currentStepIndex = min(definition.askSteps.count - 1, currentStepIndex + 1)
        onChange?()
        return true
    }

    /// Records which button ended the wizard and returns the answers.
    ///
    /// Cancelling does **not** require the step to be valid; finishing does.
    /// Returns nil when `.done` was asked for on an unsatisfied step, so a host
    /// cannot close a wizard the engine would not have let you leave.
    public func finish(_ exitButton: SwiftyWizardExitButton) -> [String: Any?]? {
        if exitButton == .done, !canLeaveCurrentStep { return nil }
        if let variable = definition.exitButtonVariable, !variable.isEmpty {
            answers[variable] = exitButton.rawValue
        }
        return answers
    }

    // MARK: - Answers

    /// Sets a raw value.
    public func setValue(_ value: Any?, for variable: String) {
        answers[variable] = value
        onChange?()
    }

    /// Sets a value from text, coerced to the question's type.
    ///
    /// Text that will not parse is stored **as text** rather than rejected:
    /// half-typed numbers are a normal state of a field, and a wizard that
    /// discarded them would fight the user mid-keystroke.
    public func setText(_ text: String, for question: WizardQuestion) {
        switch question.type {
        case .number:
            answers[question.variable] = Int(text) ?? text
        case .decimal, .money:
            answers[question.variable] = Decimal(string: text) ?? text
        default:
            answers[question.variable] = text
        }
        onChange?()
    }

    /// An answer as display text.
    public func stringValue(for variable: String) -> String {
        switch answers[variable] ?? nil {
        case let value as String: return value
        case let value as Int: return String(value)
        case let value as Double: return String(value)
        case let value as Decimal: return "\(value)"
        case .some(let value): return String(describing: value)
        case .none: return ""
        }
    }

    /// An answer as a boolean.
    ///
    /// Accepts the strings a YAML author is likely to write, because a default
    /// of `"yes"` should tick the box rather than silently mean false.
    public func boolValue(for variable: String) -> Bool {
        switch answers[variable] ?? nil {
        case let value as Bool: return value
        case let value as String: return ["true", "yes", "1"].contains(value.lowercased())
        default: return false
        }
    }

    /// An answer as a date, defaulting to now.
    public func dateValue(for variable: String) -> Date {
        (answers[variable] ?? nil) as? Date ?? Date()
    }

    // MARK: - Templating

    /// Expands `{{token}}` against the answers, then the resources.
    ///
    /// An unresolved token keeps its braces and is capitalised, so a missing
    /// value is visible on screen rather than becoming an empty gap nobody
    /// notices.
    public func renderTemplate(_ text: String) -> String {
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
            rendered += templateValue(for: key) ?? "{{\(key.capitalized)}}"
            remainder = afterStart[endRange.upperBound...]
        }

        rendered += remainder
        return rendered
    }

    private func templateValue(for key: String) -> String? {
        if let value = answers[key] ?? nil { return String(describing: value) }
        if let value = resources[key] ?? nil { return String(describing: value) }
        return nil
    }

    /// A named resource, for a host that knows what type it wants.
    public func resource<Value>(named name: String?, as type: Value.Type = Value.self) -> Value? {
        guard let name, let value = resources[name] ?? nil else { return nil }
        return value as? Value
    }

    // MARK: - Defaults

    /// Seeds unanswered questions from their declared defaults, once.
    ///
    /// Written only where there is no answer yet, so re-running this can never
    /// overwrite something the user typed.
    private func applyDefaults() {
        for step in definition.askSteps {
            for question in step.questions where answers[question.variable] == nil {
                if let value = question.defaultValue as? String {
                    answers[question.variable] = renderTemplate(value)
                } else {
                    answers[question.variable] = question.defaultValue
                }
            }
        }
    }
}
